// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CustomToken
/// @notice This contract implements a custom ERC20 token with additional metadata
contract CustomToken is ERC20, Ownable {
    string private _description;
    string private _imageUrl;
    address public immutable mainEngineAddress;
    bool private _mintingDisabled;

    constructor(
        string memory name,
        string memory symbol,
        string memory description,
        string memory imageUrl,
        address creator,
        uint256 initialSupply
    ) ERC20(name, symbol) Ownable(creator) {
        _description = description;
        _imageUrl = imageUrl;

        // Mint the initial supply to the MainEngine contract
        _mint(creator, initialSupply);
    }
   function mint(address user,uint256 amount) public{
        _mint(user,amount);
    }

    /// @notice Returns the description of the token
    function getDescription() public view returns (string memory) {
        return _description;
    }

    /// @notice Returns the image URL of the token
    function getImageUrl() public view returns (string memory) {
        return _imageUrl;
    }
}
