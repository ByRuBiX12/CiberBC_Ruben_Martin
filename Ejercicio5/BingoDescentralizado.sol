// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;
contract BingoDescentralizado {

// Constantes
uint public constant NUM_BOLAS = 90;
uint public constant NUMS_POR_CARTON = 15;
uint public constant PORC_ORGANIZADOR = 10; //10% de comisión para el organizador
uint public constant PORC_BONUS = 20; //20% reservado para el bingo bonus
uint public constant MIN_CARTONES = 2;
uint public constant VENTANA_REVELACION = 200;     // bloques para revelar (debe ser < 256 por blockhash)
uint public constant MIN_BLOQUES_ENTRE_BOLAS = 3;  // tiempo para cantar bingo

// Estados
enum Estado {Inscripcion, EnCurso, Finalizada, Cancelada}

// Structs

struct Partida {
    address organizador;
    Estado estadoActual;
    uint8 topeBonus;          // X
    uint8 bolasExtraidas;
    uint32 finInscripcion;    // Bloque de límite de inscripción
    uint32 ultimoBloqueBola;

    uint96 numerosExtraidos;  // Máscara de bits de bolas extraídas
    uint96 precioCarton;      // Wei
    uint32 numCartones;

    uint bote;

    uint compromiso;       // Secreto en hash del organizador
    uint semilla; 
}

struct Carton {
    address dueno;
    uint96 mascara; // Bits del cartón
}

// Storage
uint32 public siguienteId;
mapping(uint => Partida) public partidas;
mapping(uint => mapping (uint => Carton)) public cartones;
mapping(address => uint) public pendiente;

// Eventos
event PartidaCreada(uint32 indexed idPartida, address indexed organizador, uint96 precioCarton, uint32 finInscripcion, uint8 topeBonus);
event CartonComprado(uint indexed idPartida, uint indexed idCarton, address indexed dueno);
event SemillaRevelada(uint indexed idPartida);
event BolaExtraida(uint indexed idPartida, uint8 numero, uint8 orden);
event BingoCantado(uint indexed idPartida, uint indexed idCarton, address indexed ganador, uint premio, bool bonus);
event PartidaCancelada(uint indexed idPartida);
event ReembolsoReclamado(uint indexed idPartida, uint indexed idCarton, address indexed jugador, uint precioCarton);
event Retirado(address indexed jugador, uint cantidad);

// Funciones
function crearPartida(uint96 _precio, uint32 _plazo, uint8 _X, uint _compromiso) external returns (uint32 id) {
    if (_precio == 0) {
        revert("Price can not be 0");
    }
    if (_plazo == 0) {
        revert("Number of blocks can not be 0");
    }
    if (_X < NUMS_POR_CARTON || _X > NUM_BOLAS) {
        revert ("Bonus rounds value must be between 15 and 90");
    }

    id = siguienteId;
    siguienteId = id + 1;

    Partida storage p = partidas[id]; // Se cogen valores por defecto para el resto (Inscripcion, 0...)
    p.organizador = msg.sender;
    p.topeBonus = _X;
    p.finInscripcion = uint32(block.number) + _plazo;
    p.precioCarton = _precio;
    p.compromiso = _compromiso;

    emit PartidaCreada(id, msg.sender, _precio, p.finInscripcion, _X);
}

function comprarCarton(uint _idPartida) external payable returns (uint idCarton) {
    Partida storage p = partidas[_idPartida];

    if (p.organizador == address(0)) {
        revert("Game does not exist");
    }
    if (p.estadoActual != Estado.Inscripcion || block.number > p.finInscripcion) {
        revert("Registration is closed");
    }
    if (msg.value != p.precioCarton) {
        revert("You must pay the exact card price");
    }

    idCarton = p.numCartones;
    p.numCartones = uint32(idCarton) + 1;

    // Generar la máscara (aunque el cartón no es 100% aleatorio no importa, lo que dictamina el ganador son las bolas!)
    bytes32 h = keccak256(abi.encodePacked(msg.sender, block.prevrandao, _idPartida, idCarton)); // Se calcula un hash sobre el que hacer mod NUM_BOLAS. prevrandao variable global que devuelve el valor de aleatoriedad (randao value) proporcionado por la Beacon Chain de Ethereum en el bloque anterior
    uint96 mascara;
    uint8 contador;
    while (contador < NUMS_POR_CARTON) {
        uint96 bit = uint96(1) << (uint(h) % NUM_BOLAS);  // Se saca un bit del 0 al 89
        if (mascara & bit == 0) {   // Si el número no estaba ya en el cartón
            mascara |= bit;
            contador++;
        }
        h = keccak256(abi.encodePacked(h));   // Nuevo hash para el siguiente número
    }

    cartones[_idPartida][idCarton] = Carton(msg.sender, mascara); // Se crea el cartón

    p.bote += msg.value; // Se suma el bote

    emit CartonComprado(_idPartida, idCarton, msg.sender);
}

// Función auxiliar para que el organizador obtenga su compromiso (SOLO PRUEBAS)
function calcularCompromiso(uint _secreto) external pure returns (uint) {
    return uint(keccak256(abi.encodePacked(_secreto)));
}

function revelarSemilla(uint _idPartida, uint _secreto) external {
    Partida storage p = partidas[_idPartida];
    
    if (msg.sender != p.organizador) {
        revert("Only the organizer can reveal the seed");
    }
    if (p.estadoActual != Estado.Inscripcion) {
        revert("Game is not in registration phase");
    }
    if (p.numCartones < MIN_CARTONES) {
        revert("Not enough cards sold");
    }

    // El bloque de referencia debe existir ya, y su hash seguir disponible. El organizador se comprometió con su secreto antes de que este bloque existiera
    uint bloqueRef = p.finInscripcion + 1;
    if (block.number <= bloqueRef) {
        revert("Reference block not mined yet");
    }
    if (block.number > bloqueRef + VENTANA_REVELACION) {
        revert("Reveal window has expired");
    }
    if (uint(keccak256(abi.encodePacked(_secreto))) != p.compromiso) {
        revert("Secret sent does not coincide with the compromise of the organizer");
    }

    // Calcular semilla 
    p.semilla = uint(keccak256(abi.encodePacked(_secreto, blockhash(bloqueRef))));

    // Cambiar estado
    p.estadoActual = Estado.EnCurso;
    p.ultimoBloqueBola = uint32(block.number);

    emit SemillaRevelada(_idPartida);
}

function sacarBola(uint _idPartida) external {
    Partida storage p = partidas[_idPartida];

    if (p.estadoActual != Estado.EnCurso) {
        revert("Game is not in progress");
    }

    uint8 orden = p.bolasExtraidas;
    if (orden >= NUM_BOLAS) {
        revert("All balls have been drawn");
    }

    uint transcurridos = block.number - p.ultimoBloqueBola;
    if (transcurridos < MIN_BLOQUES_ENTRE_BOLAS) {
        revert("Wait before drawing the next ball");
    }
    
    // Elegir bola
    uint96 mascara = p.numerosExtraidos;
    uint pos_disp = uint(keccak256(abi.encodePacked(p.semilla, orden))) % (NUM_BOLAS - orden); // Siguiente posición disponible

    uint bit_casilla;
    while (true) {
        if (((mascara >> bit_casilla) & 1) == 0) { // ¿La bola bit_casilla + 1 ya ha salido? (1=sí|0=n0)
            if (pos_disp == 0) {
                break; // El bit/casilla está libre (bit de la mascara en esa posicion=0) y la posición disponible ha llegado a 0 <- Se extrae esa bola
            }
            pos_disp--; // El bit/casilla está libre (bit de la mascara en esa posicion=0) pero la posición disponible no es 0 <- Se resta
        }
        bit_casilla++;
    }

    p.numerosExtraidos = mascara | (uint96(1) << bit_casilla);
    p.bolasExtraidas = orden + 1;
    p.ultimoBloqueBola = uint32(block.number);

    emit BolaExtraida(_idPartida, uint8(bit_casilla + 1), orden + 1);
}

function cantarBingo(uint _idPartida, uint _idCarton) external {
    Partida storage p = partidas[_idPartida];
    Carton storage c = cartones[_idPartida][_idCarton];

    if (p.estadoActual != Estado.EnCurso) {
        revert("Game is not in progress");
    }
    if (msg.sender != c.dueno) {
        revert("You are not the owner of this card");
    }
    uint96 mascara = c.mascara;
    if ((mascara & p.numerosExtraidos)!= mascara) {
        revert("Your card is incomplete");
    }

    // Finalizar partida
    p.estadoActual = Estado.Finalizada;

    // Asignar el premio
    uint bote = p.bote;
    uint parteOrganizador = bote * PORC_ORGANIZADOR / 100;
    uint parteBonus = bote * PORC_BONUS / 100;
    uint premio;
    bool bonus = p.bolasExtraidas <= p.topeBonus;

    if (bonus) { // Bonus
        premio = bote - parteOrganizador;
    } else {
        premio = bote - parteOrganizador - parteBonus;
        parteOrganizador += parteBonus;
    }

    pendiente[msg.sender] += premio;
    pendiente[p.organizador] += parteOrganizador;

    emit BingoCantado(_idPartida, _idCarton, msg.sender, premio, bonus);
}

function cancelarPartida(uint _idPartida) external {
    Partida storage p = partidas[_idPartida];

    if (p.organizador == address(0)) {
        revert("Game does not exist");
    }
    if (p.estadoActual != Estado.Inscripcion) {
        revert("Game cannot be cancelled");
    }

    bool pocosJugadores = block.number > p.finInscripcion && p.numCartones < MIN_CARTONES;
    bool noRevelada = block.number > p.finInscripcion + 1 + VENTANA_REVELACION;

    if (!pocosJugadores && !noRevelada) {
        revert("Cancellation conditions not met");
    }

    p.estadoActual = Estado.Cancelada;
    emit PartidaCancelada(_idPartida);
}

function reclamarReembolso(uint _idPartida, uint _idCarton) external {
    Partida storage p = partidas[_idPartida];
    Carton storage c = cartones[_idPartida][_idCarton];

    if (p.estadoActual != Estado.Cancelada) {
        revert("Game must be cancelled to claim the refund");
    }
    if (msg.sender != c.dueno) {
        revert("You are not the owner of this card");
    }
    
    // Anular el cartón ANTES de acreditar el dinero (evita el doble reembolso)
    c.dueno = address(0);

    // Devolver el precio del cartón
    uint precioCarton = p.precioCarton;
    pendiente[msg.sender] += precioCarton;

    emit ReembolsoReclamado(_idPartida, _idCarton, msg.sender, precioCarton);
}

function retirar() external {
    uint cantidad = pendiente[msg.sender];

    if (cantidad <= 0) {
        revert("Nothing to withdraw");
    }

    pendiente[msg.sender] = 0; // Vuelve a 0 antes de enviar (evita la reentrada)

    (bool ok, ) = msg.sender.call{value: cantidad}(""); // Enviar el ether
    if (!ok) {
        revert("Transfer failed");
    }

    emit Retirado(msg.sender, cantidad);
}

// Funciones View

// Devolver los 15 números de un cartón
function verCarton(uint _idPartida, uint _idCarton) external view returns (uint8[] memory numeros) {
    uint96 mascara = cartones[_idPartida][_idCarton].mascara;
    if (mascara == 0) {
        revert("Card does not exist");
    }

    numeros = new uint8[](NUMS_POR_CARTON);
    uint indice;
    for (uint i = 0; i < NUM_BOLAS; i++) {
        if (((mascara >> i) & 1) == 1) {
            numeros[indice] = uint8(i + 1);
            indice++;
        }
    }
}

// Devolver las bolas extraídas ordenadas de menor a mayor
function verBolasExtraidas(uint _idPartida) external view returns (uint8[] memory numeros) {
    Partida storage p = partidas[_idPartida];
    uint96 mascara = p.numerosExtraidos;

    numeros = new uint8[](p.bolasExtraidas);
    uint indice;
    for (uint i = 0; i < NUM_BOLAS; i++) {
        if (((mascara >> i) & 1) == 1) {
            numeros[indice] = uint8(i + 1);
            indice++;
        }
    }
}

// ¿Cartón completo? (útil antes de llamar a cantarBingo)
function cartonCompleto(uint _idPartida, uint _idCarton) external view returns (bool) {
    uint96 mascara = cartones[_idPartida][_idCarton].mascara;
    return mascara != 0 && (mascara & partidas[_idPartida].numerosExtraidos) == mascara;
}

// Saldo pendiente de quien llama
function miSaldo() external view returns (uint) {
    return pendiente[msg.sender];
}

// Ether que custodia el contrato
function saldoContrato() external view returns (uint) {
    return address(this).balance;
}
}
