// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract QuestEscrow is ReentrancyGuard, Ownable {
    enum QuestStatus {
        Open,
        Accepted,
        Submitted,
        Completed,
        Cancelled,
        Refunded
    }

    struct Quest {
        address poster;
        address worker;
        string title;
        string description;
        uint256 reward;
        address token;
        uint256 acceptDeadline;
        uint256 reviewPeriod;
        uint256 reviewDeadline;
        QuestStatus status;
        string deliverable;
    }

    uint256 public constant FEE_BPS = 300;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public questCount;
    mapping(address => uint256) public availableFees;
    mapping(uint256 => Quest) private quests;

    constructor() Ownable(msg.sender) {}

    function createQuest(
        string calldata title,
        string calldata description,
        uint256 reward,
        uint256 acceptDeadline,
        uint256 reviewPeriod,
        address token
    ) external payable nonReentrant returns (uint256) {
        require(reward > 0, "Invalid reward");
        require(acceptDeadline > block.timestamp, "Invalid deadline");

        if (token == address(0)) {
            require(msg.value == reward, "Invalid ETH amount");
        } else {
            require(msg.value == 0, "ETH not accepted");
            IERC20(token).transferFrom(msg.sender, address(this), reward);
        }

        questCount++;

        quests[questCount] = Quest({
            poster: msg.sender,
            worker: address(0),
            title: title,
            description: description,
            reward: reward,
            token: token,
            acceptDeadline: acceptDeadline,
            reviewPeriod: reviewPeriod,
            reviewDeadline: 0,
            status: QuestStatus.Open,
            deliverable: ""
        });

        return questCount;
    }

    function acceptQuest(uint256 questId) external {
        Quest storage q = quests[questId];

        require(q.status == QuestStatus.Open, "Not open");
        require(block.timestamp <= q.acceptDeadline, "Acceptance closed");

        q.worker = msg.sender;
        q.status = QuestStatus.Accepted;
    }

    function submitWork(uint256 questId, string calldata deliverable) external {
        Quest storage q = quests[questId];

        require(q.status == QuestStatus.Accepted, "Not accepted");
        require(msg.sender == q.worker, "Only worker");

        q.deliverable = deliverable;
        q.reviewDeadline = block.timestamp + q.reviewPeriod;
        q.status = QuestStatus.Submitted;
    }

    function approveAndPay(uint256 questId) external nonReentrant {
        Quest storage q = quests[questId];

        require(msg.sender == q.poster, "Only poster");
        require(q.status == QuestStatus.Submitted, "Not submitted");

        _payWorker(q);
        q.status = QuestStatus.Completed;
    }

    function claimTimeoutPayout(uint256 questId) external nonReentrant {
        Quest storage q = quests[questId];

        require(msg.sender == q.worker, "Only worker");
        require(q.status == QuestStatus.Submitted, "Not submitted");
        require(block.timestamp > q.reviewDeadline, "Review active");

        _payWorker(q);
        q.status = QuestStatus.Completed;
    }

    function cancelQuest(uint256 questId) external nonReentrant {
        Quest storage q = quests[questId];

        require(msg.sender == q.poster, "Only poster");
        require(q.status == QuestStatus.Open, "Not open");

        q.status = QuestStatus.Cancelled;
        _transfer(q.token, q.poster, q.reward);
    }

    function refundPoster(uint256 questId) external nonReentrant {
        Quest storage q = quests[questId];

        require(msg.sender == q.poster, "Only poster");
        require(q.status == QuestStatus.Submitted, "Not submitted");
        require(block.timestamp > q.reviewDeadline, "Review active");

        q.status = QuestStatus.Refunded;
        _transfer(q.token, q.poster, q.reward);
    }

    function withdrawFees(address token) external onlyOwner nonReentrant {
        uint256 amount = availableFees[token];
        require(amount > 0, "No fees");

        availableFees[token] = 0;
        _transfer(token, msg.sender, amount);
    }

    function getAvailableFees(address token) external view returns (uint256) {
        return availableFees[token];
    }

    function getQuest(uint256 questId)
        external
        view
        returns (
            address poster,
            address worker,
            string memory title,
            string memory description,
            uint256 reward,
            address token,
            uint256 acceptDeadline,
            uint256 reviewPeriod,
            uint256 reviewDeadline,
            uint8 status,
            string memory deliverable
        )
    {
        Quest storage q = quests[questId];

        return (
            q.poster,
            q.worker,
            q.title,
            q.description,
            q.reward,
            q.token,
            q.acceptDeadline,
            q.reviewPeriod,
            q.reviewDeadline,
            uint8(q.status),
            q.deliverable
        );
    }

    function _payWorker(Quest storage q) internal {
        uint256 fee = (q.reward * FEE_BPS) / BPS_DENOMINATOR;
        uint256 payout = q.reward - fee;

        availableFees[q.token] += fee;
        _transfer(q.token, q.worker, payout);
    }

    function _transfer(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool success, ) = payable(to).call{value: amount}("");
require(success, "ETH transfer failed");
        } else {
            IERC20(token).transfer(to, amount);
        }
    }
}