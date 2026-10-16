# OpenZeppelin ERC-721

## Pruebas realizadas

Se ha implementado y probado el contrato `MyToken`, basado en ERC-721 de OpenZeppelin, en Remix.

- **`safeMint`:** se han creado correctamente dos NFT desde la cuenta 0, utilizando una URI de ejemplo para cada uno.
- **`ownerOf`:** se ha comprobado que cada NFT pertenece a la cuenta correspondiente.
- **`balanceOf`:** devuelve `1` tras crear el primer NFT y `2` tras crear el segundo. Después de transferir un NFT, los balances se actualizan correctamente.
- **`tokenURI`:** devuelve la URI de ejemplo asignada durante la creación de cada NFT.
- **Control de acceso:** se ha comprobado que otra cuenta no puede ejecutar `safeMint`, ya que la función está restringida al propietario del contrato.
- **`transferFrom`:** desde la cuenta 1, se ha transferido el segundo NFT (ID `1`) a la cuenta 2. La operación se ha completado correctamente y se ha verificado mediante `balanceOf`.

Todas las pruebas realizadas han funcionado según lo esperado.
