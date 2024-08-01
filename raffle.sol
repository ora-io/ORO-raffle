// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract AddressCompress {
    
    mapping (address => uint32) public uidOf;
    mapping (uint32 => address) public addrOf;
    
    uint32 public topUid;
    
    function register(address _addr) public returns (uint32 uid) {
        require(uidOf[_addr] == 0, "Address already registerered");
        uid = ++topUid;
        uidOf[_addr] = uid;
        addrOf[uid] = _addr;
    }
}

/* raffleBullet is a token contract for raffle activity
 * sponsor can host several raffle activities at the same time and issue independent token for each activity
 * sponsor provides on-ramp service on web page, user can pay USD / USDT to exchange raffleBullet
 * sponsor calls mint function to issue raffleBullet to user after receiving payment
 * raffleBullet can be transferred freely between users
 * raffleBullet can only be consumed by raffle activity contract
 * when user participates in raffle activity, raffle contract automatically calls 
 * consume function of raffleBullet contract to deduct user's raffleBullet, 
 * meanwhile user exchanges raffleBullet for winning chance
 */

contract RaffleBullet {
    string public name;
    string public symbol;
    uint8 public decimals;
    address public sponsor;
    address public raffleContract;
    AddressCompress public addressCompress;
    mapping (uint32 => uint32) private balances;
    
    modifier onlySponsor() {
        require(msg.sender == sponsor, "Only sponsor can call this function");
        _;
    }
    
    modifier onlyraffle() {
        require(msg.sender == raffleContract, "Only raffle contract can call this function");
        _;
    }
    
    event Initraffle();
    event Transfer(address indexed from, address indexed receiver, uint value);
    event Mint(address indexed receiver, uint value, uint txIndex);

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _addressCompress) {
        sponsor = msg.sender;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        addressCompress = AddressCompress(_addressCompress);
    }
    
    function balanceOf(address _addr) public view returns (uint balance) {
        balance = balances[addressCompress.uidOf(_addr)];
    }
    
    function initraffle(address _raffleContract) public onlySponsor {
        require(raffleContract == address(0), "raffleContract address already set");
        raffleContract = _raffleContract;
        emit Initraffle();
    }
    
    function mint(address _receiver, uint32 _value, uint _txIndex) public onlySponsor {
        uint32 uid = addressCompress.uidOf(_receiver);
        if (uid == 0)
            uid = addressCompress.register(_receiver);
        
        require(balances[uid] + _value >= balances[uid], "Overflow error");
        balances[uid] += _value;
        emit Mint(_receiver, _value, _txIndex);
    }
    
    function consume(uint32 _participantsUid, uint32 _value) external onlyraffle returns (bool success) {
        require(balances[_participantsUid] >= _value, "Insufficient balance");
        balances[_participantsUid] -= _value;
        return true;
    }
    
    function transfer(address _receiver, uint32 _value) public {
        uint32 senderUid = addressCompress.uidOf(msg.sender);
        require(senderUid != 0, "Sender address not registered");
        require(balances[senderUid] >= _value, "Insufficient balance");
        uint32 receiverUid = addressCompress.uidOf(_receiver);
        if (receiverUid == 0)
            receiverUid = addressCompress.register(_receiver);
        require(balances[receiverUid] + _value >= balances[receiverUid], "Overflow error");
        balances[senderUid] -= _value;
        balances[receiverUid] += _value;
        emit Transfer(msg.sender, _receiver, _value);
    }
}

contract RaffleContract {

    //import "@ora/oro.sol";


    address public sponsor;
    RaffleBullet public raffleBullet;
    AddressCompress public addressCompress;
    uint256 public ORO_randoness;
    
    //User settings
    int32 public premium;
    
    struct Reward {
        string name;
        address tokenAddress;
        uint256 amount;
    }
    struct Goods {
        Reward reward;
        uint32 totalChances;
        uint32 soldChances;
        string description;
        uint32 winnerId;
        uint32[] participants;
    }
    
    Goods[] private goodList;
    
    modifier onlySponsor() {
        require(msg.sender == sponsor, "Only sponsor can call this function");
        _;
    }
    
    event InitraffleBullet();
    event NewParticipant(uint256 indexed goodId, address indexed participant);
    event GoodPosted(uint256 indexed goodId, string name, address tokenAddress, uint256 amount);
    event BuyBullet(address indexed consumer, uint beginUserId, uint txIndex);
    event NotifyWinnerResult(uint goodsId, uint winner);

    constructor(uint256 _ORO_randoness, address _raffleBullet, address _addressCompress, int32 _defaultPremium) {
        sponsor = msg.sender;
        raffleBullet = RaffleBullet(_raffleBullet);
        addressCompress = AddressCompress(_addressCompress);
        setPremium(_defaultPremium);
        ORO_randoness = _ORO_randoness;
    }

    function setPremium(int32 _premium) public onlySponsor {
        premium = _premium;
    }

    function enterRaffle(uint256 _goodId) external {
        require(_goodId < goodList.length, "Good does not exist");
        Goods storage good = goodList[_goodId];
        require(good.soldChances < good.totalChances, "All chances sold");
        good.participants.push(addressCompress.uidOf(msg.sender));
        good.soldChances++;
        emit NewParticipant(_goodId, msg.sender);
    }

function postGood(string memory _name, address _tokenAddress, uint256 _amount, uint32 _totalChances, string memory _description) external onlySponsor {
        Reward memory reward = Reward({
            name: _name,
            tokenAddress: _tokenAddress,
            amount: _amount
        });
        Goods memory good = Goods({
            reward: reward,
            totalChances: _totalChances,
            soldChances: 0,
            description: _description,
            winnerId: 0,
            participants: new uint32[](0)
        });
        goodList.push(good);
        emit GoodPosted(goodList.length - 1, _name, _tokenAddress, _amount);
    }
    
    function getUser(uint32 _goodsId, uint32 _userId) external view returns (address) {
        Goods storage goods = goodList[_goodsId - 1];
        uint32 userIndex = _userId - 1;
        uint32 uid = goods.participants[userIndex];
        return address(uint160(uid));
    }
    
    //called by sponsor to buy raffleBullet for user after receiving payment
    function buyBullet(uint32 _goodsId, uint32 _quantity, uint _txIndex) external {
        Goods storage goods = goodList[_goodsId - 1];
        require(goods.soldChances + _quantity <= goods.totalChances, "Exceeds available chances");
        uint32 uid = addressCompress.uidOf(msg.sender);
        require(raffleBullet.balanceOf(msg.sender) >= _quantity, "Insufficient raffleBullet");
        raffleBullet.consume(uid, _quantity);

        emit BuyBullet(msg.sender, uid, _txIndex);
        goods.soldChances += _quantity;

        // reflect multiple chances in the participants array for higher winning probability
        for (uint32 i = 0; i < _quantity; i++) {
            goods.participants.push(uid);
        }

        if (goods.soldChances == goods.totalChances) {
            determineWinner(_goodsId);
        }
    }

     // Function to request random number from ORO
    //TODO

    // Callback function used by ORO to send random number
    //TODO;

    function determineWinner(uint32 _goodsId) internal {
        Goods storage goods = goodList[_goodsId - 1];
        require(goods.soldChances == goods.totalChances, "Chances not sold out");

        // Use the ORO random number to pick the winner fairly and verifiably
        uint random = ORO_randoness;
        goods.winnerId = uint32(random % goods.totalChances + 1);

        emit NotifyWinnerResult(_goodsId, goods.winnerId);
    }

    function getParticipants(uint256 _goodId) external view returns (uint32[] memory) {
        require(_goodId < goodList.length, "Good does not exist");
        return goodList[_goodId].participants;
    }

    // Function to claim the prize by the winner
    function claimReward(uint256 _goodId) external {
        Goods storage good = goodList[_goodId];
        require(good.winnerId != 0, "Winner not declared yet");
        require(msg.sender == address(uint160(good.participants[good.winnerId - 1])), "Only the winner can claim the reward");

        IERC20 token = IERC20(good.reward.tokenAddress);
        require(token.transfer(msg.sender, good.reward.amount), "Token transfer failed");
    }
}
  