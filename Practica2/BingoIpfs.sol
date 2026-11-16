// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract BingoIpfs {
    struct Acta {
        address autor;
        string cid;
    }

    mapping(uint => Acta) public actas;

    event ActaRegistrada(uint indexed idPartida, address indexed autor, string cid);

    function registrarActa(uint _idPartida, string calldata _cid) external {
        if (actas[_idPartida].autor != address(0)) {
            revert("Record already registered");
        }
        actas[_idPartida] = Acta(msg.sender, _cid);
        emit ActaRegistrada(_idPartida, msg.sender, _cid);
    }
}
