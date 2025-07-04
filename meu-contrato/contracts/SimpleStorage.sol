// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract SimpleStorage {
    uint256 private number;

    function store(uint256 _newNumber) public {
        number = _newNumber;
    }

    function retrieve() public view returns (uint256) {
        return number;
    }
}
