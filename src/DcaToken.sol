// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title DcaToken — demo ERC20 bought by the DCA vault (testnet only).
/// @notice Minimal ERC20 (no external dependencies). 1,000,000 tokens minted
///         to the deployer; extra minting is open for testnet liquidity seeding.
contract DcaToken {
    string public name = "DCA Demo Token";
    string public symbol = "DCAT";
    uint8 public decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        _mint(msg.sender, 1_000_000 ether);
    }

    function _mint(address to_, uint256 amount_) internal {
        totalSupply += amount_;
        balanceOf[to_] += amount_;
        emit Transfer(address(0), to_, amount_);
    }

    function mint(address to_, uint256 amount_) external {
        _mint(to_, amount_);
    }

    function transfer(address to_, uint256 amount_) external returns (bool) {
        require(balanceOf[msg.sender] >= amount_, "DcaToken: insufficient balance");
        balanceOf[msg.sender] -= amount_;
        balanceOf[to_] += amount_;
        emit Transfer(msg.sender, to_, amount_);
        return true;
    }

    function approve(address spender_, uint256 amount_) external returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) external returns (bool) {
        require(balanceOf[from_] >= amount_, "DcaToken: insufficient balance");
        require(
            allowance[from_][msg.sender] >= amount_,
            "DcaToken: insufficient allowance"
        );
        allowance[from_][msg.sender] -= amount_;
        balanceOf[from_] -= amount_;
        balanceOf[to_] += amount_;
        emit Transfer(from_, to_, amount_);
        return true;
    }
}
