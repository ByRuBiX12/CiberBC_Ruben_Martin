import hashlib
import os
import tempfile

HASH_SIZE = 32                                  # un hash ocupa 32 bytes
SCOOP_SIZE = 64                                 # un scoop = 2 hashes = 64 bytes
SCOOPS_PER_NONCE = 64                           # en la red real: 4096
HASHES_PER_NONCE = SCOOPS_PER_NONCE * 2         # en la red real: 8192

ROUNDS = 1000                                   # bloques que se simulan

# Dificultad de la red. Cuanto mayor es, menores son las deadlines.
BASE_TARGET = 2**64 // 240_000

# Firma de generación inicial (fija para que la demo sea repetible).
GENESIS_SIGNATURE = hashlib.sha256(b"GENESIS").digest()

# Capacidad de cada minero (nonces guardados en disco)
CAPACITIES = {
    "Alice": 100,
    "Bob": 300,
    "Charlie": 600,
}

# En la red real se usa shabal256.
def sha256(data):
    return hashlib.sha256(data).digest()

def get_account_id(name):
    """Identificador de 8 bytes de un minero (a partir de su nombre)."""
    return sha256(name.encode())[:8]


# ------------------------------------------------------------------
# FASE 1: TRAZADO/PLOTTING
# ------------------------------------------------------------------
def generate_nonce(account_id, nonce_number): # Nonce = cadena de hashes
    seed = account_id + nonce_number.to_bytes(8, "big")

    hashes = []
    previous_hash = seed

    for _ in range(HASHES_PER_NONCE):
        new_hash = sha256(previous_hash + seed)
        hashes.append(new_hash)
        previous_hash = new_hash

    # Los hashes se generan de atrás hacia delante -> se invierte la lista.
    hashes.reverse()

    return b"".join(hashes)


def get_scoop(nonce_data, scoop_number): # scoop = 2 hashes = 64 bytes dentro del nonce
    start = scoop_number * SCOOP_SIZE
    end = start + SCOOP_SIZE
    return nonce_data[start:end]


def create_plot_file(path, name, capacity):
    account_id = get_account_id(name)

    # 1) Generar todos los nonces.
    all_nonces = []
    for nonce_number in range(capacity):
        nonce_data = generate_nonce(account_id, nonce_number)
        all_nonces.append(nonce_data)

    # 2) Escribirlos en disco ordenados por scoop.
    with open(path, "wb") as plot_file:
        for scoop_number in range(SCOOPS_PER_NONCE):
            for nonce_data in all_nonces:
                scoop = get_scoop(nonce_data, scoop_number)
                plot_file.write(scoop)


def create_all_plots(temp_dir): # Crea el plot de cada minero y devuelve dónde está cada uno.
    plot_files = {}

    for name in CAPACITIES:
        capacity = CAPACITIES[name]
        path = os.path.join(temp_dir, name + ".plot")

        create_plot_file(path, name, capacity)

        plot_files[name] = {"path": path, "capacity": capacity}
        size = os.path.getsize(path)
        print(f"  {name}: {capacity} nonces -> {size} bytes en disco")

    return plot_files


# ------------------------------------------------------------------
# FASE 2: MINADO
# ------------------------------------------------------------------
def select_scoop(generation_signature, height):  # La red decide un scoop a leer. No se puede predecir antes de conocer la generation signature del bloque anterior.
    selection_hash = sha256(generation_signature + height.to_bytes(8, "big"))
    number = int.from_bytes(selection_hash, "big")
    return number % SCOOPS_PER_NONCE


def read_scoops_from_disk(path, capacity, scoop_number):
    position = scoop_number * capacity * SCOOP_SIZE
    amount_to_read = capacity * SCOOP_SIZE

    with open(path, "rb") as plot_file:
        plot_file.seek(position)
        return plot_file.read(amount_to_read)


def calculate_deadline(generation_signature, scoop): # Deadline = hash(generation signature + scoop) / base target.
    hash_result = sha256(generation_signature + scoop)
    hit = int.from_bytes(hash_result[:8], "little")
    return hit / BASE_TARGET


def mine_block(generation_signature, height, plot_files):
    scoop_number = select_scoop(generation_signature, height)
    claims = {}

    for name in plot_files:
        path = plot_files[name]["path"]
        capacity = plot_files[name]["capacity"]

        # Una única lectura a disco con el scoop de todos los nonces.
        scoops_data = read_scoops_from_disk(path, capacity, scoop_number)

        # Una deadline por nonce; nos quedamos con la menor.
        best_deadline = None
        best_nonce = None

        for nonce_number in range(capacity):
            start = nonce_number * SCOOP_SIZE
            end = start + SCOOP_SIZE
            scoop = scoops_data[start:end]

            deadline = calculate_deadline(generation_signature, scoop)

            if best_deadline is None or deadline < best_deadline:
                best_deadline = deadline
                best_nonce = nonce_number

        claims[name] = {
            "deadline": best_deadline,
            "nonce": best_nonce,
            "bytes_read": len(scoops_data),
        }

    return scoop_number, claims


def verify_claim(generation_signature, height, name, nonce_number, claimed_deadline): # Comprobación que hace cualquier nodo de la red.
    account_id = get_account_id(name)
    nonce_data = generate_nonce(account_id, nonce_number)

    scoop_number = select_scoop(generation_signature, height)
    scoop = get_scoop(nonce_data, scoop_number)

    real_deadline = calculate_deadline(generation_signature, scoop)
    if real_deadline != claimed_deadline:
        print(f"  >> VERIFICACIÓN: {name} dice {claimed_deadline:.1f} s, calculado {real_deadline:.1f} s")
    return real_deadline == claimed_deadline


def choose_winner(generation_signature, height, claims): # Elige el minero con la menor deadline, verificando que sea válida.
    pending = list(claims.keys())

    while len(pending) > 0:
        # Buscar, entre los que quedan, el de menor deadline.
        best_name = None
        for name in pending:
            if best_name is None or claims[name]["deadline"] < claims[best_name]["deadline"]:
                best_name = name

        claim = claims[best_name]
        is_valid = verify_claim(
            generation_signature, height, best_name,
            claim["nonce"], claim["deadline"],
        )

        if is_valid:
            return best_name

        print(f"  >> RECHAZADO: la propuesta de {best_name} "
              f"(deadline {claim['deadline']:.1f} s) NO es válida")
        pending.remove(best_name)

    return None


def simulate_blocks(plot_files, rounds, detailed_blocks): # Simula la generación de varios bloques y devuelve cuántos ganó cada minero.
    wins = {}
    for name in plot_files:
        wins[name] = 0

    generation_signature = GENESIS_SIGNATURE

    for height in range(1, rounds + 1):
        scoop_number, claims = mine_block(generation_signature, height, plot_files)
        winner = choose_winner(generation_signature, height, claims)
        wins[winner] += 1

        # Solo se detallan los primeros bloques.
        if height <= detailed_blocks:
            print(f"\nBloque {height}")
            print(f"  Scoop elegido por la red: {scoop_number} "
                  f"(de {SCOOPS_PER_NONCE})")

            for name in claims:
                plot_size = os.path.getsize(plot_files[name]["path"])
                read = claims[name]["bytes_read"]
                print(f"  {name}: leyó {read} de {plot_size} bytes del disco ({read/plot_size*100:.1f}%)")
                print(f"    Mejor nonce: {claims[name]['nonce']}"
                      f" | deadline: {claims[name]['deadline']:.1f} s")

            print(f"  Ganador: {winner}")

        # La nueva firma depende del ganador: no se puede prever.
        generation_signature = sha256(generation_signature + get_account_id(winner))

    return wins


def print_results(wins, plot_files, rounds): # Compara las victorias observadas con el reparto proporcional.
    total_nonces = 0
    for name in plot_files:
        total_nonces += plot_files[name]["capacity"]

    for name in plot_files:
        capacity = plot_files[name]["capacity"]
        expected = capacity / total_nonces * 100
        observed = wins[name] / rounds * 100

        print(f"\n{name}")
        print(f"  Nonces almacenados: {capacity}")
        print(f"  Victorias: {wins[name]}/{rounds}")
        print(f"  Porcentaje observado: {observed:.2f}%")
        print(f"  Porcentaje esperado por capacidad: {expected:.2f}%")


# ------------------------------------------------------------------
# FASE 3: RESILIENCIA (tolerancia a fallos)
# ------------------------------------------------------------------
def corrupt_scoop(path, capacity, scoop_number, nonce_number): # Simula un fallo de disco: cambia un byte de un scoop.
    position = scoop_number * capacity * SCOOP_SIZE + nonce_number * SCOOP_SIZE

    with open(path, "r+b") as plot_file:
        plot_file.seek(position)
        original = plot_file.read(SCOOP_SIZE)

        damaged = bytearray(original)
        damaged[0] = damaged[0] ^ 0xFF          # se invierte el primer byte

        plot_file.seek(position)
        plot_file.write(bytes(damaged))

    return original


def restore_scoop(path, capacity, scoop_number, nonce_number, original): # Restaura el scoop a su estado original tras un fallo de disco.
    position = scoop_number * capacity * SCOOP_SIZE + nonce_number * SCOOP_SIZE

    with open(path, "r+b") as plot_file:
        plot_file.seek(position)
        plot_file.write(original)


def test_corrupted_disk(plot_files): # Solo se pierde el nonce corrupto; el resto del plot sigue funcionando.
    print("\n--- PRUEBA 1: corrupción de datos en el disco ---")
    height = 1
    generation_signature = GENESIS_SIGNATURE

    # Bloque normal, sin fallos.
    scoop_number, claims = mine_block(generation_signature, height, plot_files)
    winner = choose_winner(generation_signature, height, claims)
    nonce_number = claims[winner]["nonce"]

    print(f"  Antes del fallo: gana {winner} con el nonce {nonce_number} "
          f"(deadline {claims[winner]['deadline']:.1f} s)")

    # Fallo: se cambia 1 byte del scoop ganador.
    path = plot_files[winner]["path"]
    capacity = plot_files[winner]["capacity"]
    original = corrupt_scoop(path, capacity, scoop_number, nonce_number)
    print(f"  FALLO: se altera 1 byte del scoop {scoop_number} del nonce "
          f"{nonce_number} en el disco de {winner}")

    # Se repite el mismo bloque con el disco dañado.
    scoop_number, claims = mine_block(generation_signature, height, plot_files)
    print(f"  {winner} ahora propone el nonce {claims[winner]['nonce']} "
          f"(deadline {claims[winner]['deadline']:.1f} s)")

    new_winner = choose_winner(generation_signature, height, claims)
    print(f"  Después del fallo: gana {new_winner}")
    print(f"  Solo se perdió 1 de los {capacity} nonces de {winner}; "
          f"los demás siguen siendo válidos.")

    # Se deja el disco como estaba para las siguientes pruebas.
    restore_scoop(path, capacity, scoop_number, nonce_number, original)


def test_fake_claim(plot_files): # Un minero intenta hacer trampa modificando su deadline a mano. Los demás nodos lo detectan y lo descartan.
    print("\n--- PRUEBA 2: minero tramposo (dato modificado a mano) ---")
    height = 1
    generation_signature = GENESIS_SIGNATURE

    scoop_number, claims = mine_block(generation_signature, height, plot_files)
    honest_winner = choose_winner(generation_signature, height, claims)
    print(f"  Sin trampa: gana {honest_winner}")

    # Se elige como tramposo a un minero que no iba a ganar.
    cheater = None
    for name in claims:
        if name != honest_winner:
            cheater = name
            break

    print(f"  FALLO: {cheater} cambia a mano su deadline a 0.5 s")
    claims[cheater]["deadline"] = 0.5

    winner = choose_winner(generation_signature, height, claims)
    print(f"  Resultado: gana {winner} (la trampa de {cheater} no sirvió)")


def test_offline_miner(plot_files): # Un minero se desconecta de la red. Los demás siguen generando bloques sin él.
    print("\n--- PRUEBA 3: un minero se cae de la red ---")
    offline = "Charlie"
    print(f"  FALLO: {offline} se desconecta")

    remaining_plots = {}
    for name in plot_files:
        if name != offline:
            remaining_plots[name] = plot_files[name]

    wins = simulate_blocks(remaining_plots, ROUNDS, detailed_blocks=3)
    print(f"\n  La red siguió generando los {ROUNDS} bloques sin {offline}.")
    print_results(wins, remaining_plots, ROUNDS)

# ===================================================================

def main():
    print("=== DEMO PROOF OF CAPACITY ===")

    # Los plots se guardan en una carpeta temporal que se borra al terminar.
    with tempfile.TemporaryDirectory() as temp_dir:

        print("\nFase 1: plotting (generar nonces y guardarlos en disco)")
        plot_files = create_all_plots(temp_dir)

        print("\nFase 2: minado (leer solo el scoop elegido por la red)")
        wins = simulate_blocks(plot_files, ROUNDS, detailed_blocks=3)

        print("\n=== RESULTADOS ===")
        print_results(wins, plot_files, ROUNDS)

        print("\n\n=== FASE 3: RESILIENCIA ===")
        test_corrupted_disk(plot_files)
        test_fake_claim(plot_files)
        test_offline_miner(plot_files)


if __name__ == "__main__":
    main()
