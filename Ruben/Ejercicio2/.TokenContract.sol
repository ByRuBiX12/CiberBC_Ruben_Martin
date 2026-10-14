// SPDX-License-Identifier: Unlicenced
pragma solidity ^0.8.30;
contract TokenContract {

    address public owner;
    struct Receivers {
        string name;
        uint256 tokens;
    }
    mapping(address => Receivers) public users;

    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    constructor(){
        owner = msg.sender;
        users[owner].tokens = 100;
    }

    function double(uint _value) public pure returns (uint){
        return _value*2;
    }

    function register(string memory _name) public{
        users[msg.sender].name = _name;
    }

    function giveToken(address _receiver, uint256 _amount) onlyOwner public{
        require(users[owner].tokens >= _amount);
        users[owner].tokens -= _amount;
        users[_receiver].tokens += _amount;
    }

    function buyTokens(uint256 _amount) public payable {
        uint256 cost = _amount * 5 ether; // El coste será de cada token por los 5 Ether que cuesta cada uno
        require(msg.value >= cost, "Not enough Ether sent"); // Se comprueba la cantidad de Ether enviado
        require(users[owner].tokens >= _amount, "Not enough tokens available"); // Se comprueba de cuántos tokens dispone el propietario
        users[owner].tokens -= _amount; // Se restan al propietario los tokens que ha perdido
        users[msg.sender].tokens += _amount; // Se suman al comprador los tokens que ha adquirido
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance; // Se muestra la cantidad de Ether que hay en el contrato inteligente
    }
}
