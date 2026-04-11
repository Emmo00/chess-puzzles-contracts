// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StablecoinReceiver is Ownable {
    using SafeERC20 for IERC20;

    address public treasury;

    event Deposited(address indexed payer, address indexed token, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    constructor(address _treasury) Ownable(msg.sender) {
        require(_treasury != address(0), "treasury zero address");
        treasury = _treasury;
    }

    function deposit(address token, uint256 amount) external {
        require(token != address(0), "token zero");
        require(amount > 0, "amount zero");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, token, amount);
    }

    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // Generic withdrawal
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        require(token != address(0), "token zero");
        require(to != address(0), "to zero");
        require(amount > 0, "amount zero");

        uint256 bal = IERC20(token).balanceOf(address(this));
        require(amount <= bal, "insufficient balance");

        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    // Convenience: withdraw everything to treasury
    function withdrawAllToTreasury(address token) external onlyOwner {
        require(treasury != address(0), "treasury not set");
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "no balance");

        IERC20(token).safeTransfer(treasury, bal);
        emit Withdrawn(token, treasury, bal);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "treasury zero");
        emit TreasuryUpdated(treasury, _treasury);
        treasury = _treasury;
    }
}
