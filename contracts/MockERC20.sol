pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockERC20FeeOnTransfer is MockERC20 {
    uint256 public feePercentage;

    constructor(string memory name, string memory symbol, uint256 _feePercentage) MockERC20(name, symbol) {
        feePercentage = _feePercentage;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountToSend = amount - fee;
        _transfer(msg.sender, to, amountToSend);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountToSend = amount - fee;
        _approve(from, msg.sender, allowance(from, msg.sender) - amount);
        _transfer(from, to, amountToSend);
        return true;
    }
}