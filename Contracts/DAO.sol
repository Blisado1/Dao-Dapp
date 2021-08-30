// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * DAO contract:
 * 1. Collects investors money (ether) & allocate shares
 * 2. Keep track of investor contributions with shares
 * 3. Allow investors to transfer shares
 * 4. allow investment proposals to be created and voted
 * 5. execute successful investment proposals (i.e send money)
 * 6. Initial State has been set to 50 people, 365 days of contributions, 24 hours for voting
 */

interface IERC20Token {
    function transfer(address, uint256) external returns (bool);

    function approve(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function allowance(address, address) external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract DAO {
    struct Proposal {
        uint256 id;
        string name;
        uint256 amount;
        address payable recipient;
        uint256 votes;
        uint256 end;
        bool executed;
    }

    mapping(address => bool) public investors;
    mapping(address => uint256) public shares;
    mapping(address => mapping(uint256 => bool)) public votes;
    mapping(uint256 => Proposal) public proposals;
    uint256 public totalShares;
    uint256 public availableFunds;
    uint256 public contributionEnd;
    uint256 public nextProposalId;
    uint256 public voteTime;
    uint256 public quorum;
    address public admin;

    address internal cUsdTokenAddress =
        0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;

    constructor(
        uint256 contributionTime,
        uint256 _voteTime,
        uint256 _quorum
    ) {
        require(
            _quorum > 0 && _quorum < 100,
            "quorum must be between 0 and 100"
        );
        contributionEnd = block.timestamp + contributionTime * 1 days;
        voteTime = _voteTime * 1 hours;
        quorum = _quorum;
        admin = msg.sender;
    }

    function contribute(uint256 _amount)
        external
        payable
        contributionTimeExpired
    {
        require(
            IERC20Token(cUsdTokenAddress).transferFrom(
                msg.sender,
                address(this),
                _amount
            ),
            "Transfer failed"
        );
        investors[msg.sender] = true;
        shares[msg.sender] += _amount;
        totalShares += _amount;
        availableFunds += _amount;
    }

    function redeemShares(uint256 _amount) external {
        require(shares[msg.sender] >= _amount, "not enough shares");
        require(availableFunds >= _amount, "not enough available funds");
        shares[msg.sender] -= _amount;
        availableFunds -= _amount;
        IERC20Token(cUsdTokenAddress).transfer(payable(msg.sender), _amount);
    }

    function transferShares(uint256 amount, address to) external {
        require(shares[msg.sender] >= amount, "not enough shares");
        shares[msg.sender] -= amount;
        shares[to] += amount;
        investors[to] = true;
    }

    function createProposal(
        string memory name,
        uint256 amount,
        address payable recipient
    ) public onlyInvestors {
        require(availableFunds >= amount, "amount too big");
        proposals[nextProposalId] = Proposal(
            nextProposalId,
            name,
            amount,
            recipient,
            0,
            block.timestamp + voteTime,
            false
        );
        availableFunds -= amount;
        nextProposalId++;
    }

    function vote(uint256 proposalId) external onlyInvestors {
        Proposal storage proposal = proposals[proposalId];
        require(
            votes[msg.sender][proposalId] == false,
            "investor can only vote once for a proposal"
        );
        require(
            block.timestamp < proposal.end,
            "can only vote until proposal end date"
        );
        votes[msg.sender][proposalId] = true;
        proposal.votes += shares[msg.sender];
    }

    function executeProposal(uint256 proposalId) external onlyAdmin {
        Proposal storage proposal = proposals[proposalId];
        require(
            block.timestamp >= proposal.end,
            "cannot execute proposal before end date"
        );
        require(
            proposal.executed == false,
            "cannot execute proposal already executed"
        );
        require(
            (proposal.votes / totalShares) * 100 >= quorum,
            "cannot execute proposal with votes # below quorum"
        );
        _transferFunds(proposal.amount, proposal.recipient);
    }

    function withdrawFunds(uint256 amount, address payable to)
        external
        onlyAdmin
    {
        _transferFunds(amount, to);
    }

    function _transferFunds(uint256 amount, address payable to) internal {
        require(amount <= availableFunds, "not enough availableFunds");
        availableFunds -= amount;
        IERC20Token(cUsdTokenAddress).transfer(to, amount);
    }

    modifier onlyInvestors() {
        require(investors[msg.sender] == true, "only investors");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin");
        _;
    }

    modifier contributionTimeExpired() {
        require(
            block.timestamp < contributionEnd,
            "cannot contribute after contributionEnd"
        );
        _;
    }
}
