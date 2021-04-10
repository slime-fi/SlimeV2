 pragma solidity 0.6.12;

import '../libs/SafeMath.sol';
import '../libs/IBEP20.sol';
import '../libs/SafeBEP20.sol';
import '../token/SlimeTokenV2.sol';
import '../libs/ReentrancyGuard.sol';

//  referral
interface SlimeFriends {
    function setSlimeFriend(address farmer, address referrer) external;
    function getSlimeFriend(address farmer) external view returns (address);
}

 contract IRewardDistributionRecipient is Ownable {
    address public rewardReferral;
    address public rewardVote;


    function setRewardReferral(address _rewardReferral) external onlyOwner {
        rewardReferral = _rewardReferral;
    }

}

contract SlimeSwapVestingFarmV2   is IRewardDistributionRecipient , ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // Total SlimeV1 deposited
        uint256 amountV2;     // Total SlimeV2 payed
        uint256 rewardAmount;  //Max reward can get

        uint lastDeposit; // last deposit block
        uint rewardUpTo; // last block where user will get 100% vesting amount payed
        uint256 slimiesPerBlock; // custom user block rate

        uint256 lastRewardBlock;  // Last block number that slimes distribution occurs.

    }


    mapping ( address => UserInfo) public userInfo;


    uint256[1] public fees;

    uint256 public constant MAX_FEE_ALLOWED = 100; //10%



    event Deposit(address indexed user,   uint256 amount);
    event EnableDeposit(bool status);
    event DepositFor(address indexed user,address indexed userTo, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event ReferralPaid(address indexed user,address indexed userTo, uint256 reward);
    event Burned(uint256 reward);


    event Swap(address indexed user, uint256 amountIn,uint256 amountOut);
    event UpdateSwapRate(uint256 indexed previousRate, uint256 indexed newRate);

    SlimeTokenV2 public slimeV1;
    SlimeTokenV2 public slimeV2;


    uint public  vestingPeriod = (31*28800);

    uint public  vestignRate = 75; // 75 %
    uint public  vestingBonus = 120; // +20 % bonus rate
    // 1e18 = 1:1
    uint256 public swapRate = 1e17;

    address public  dead = address(0xdead);

    uint256 public totalDeposited = 0;

    uint256 public totalV2Minted = 0;

    uint256 public actualV2PerBlock = 0;

    uint public startBlock = 0;

    bool public enableDeposits = true;

    constructor(
         SlimeTokenV2 _slimeV1,
        SlimeTokenV2 _slimeV2,
        uint _startBlock
    ) public {
        slimeV1 = _slimeV1;
        slimeV2 = _slimeV2;
        startBlock= _startBlock;

        fees[0] = 5;  // referral Fee (Slime) = 0.5%
    }


    mapping(IBEP20 => bool) public tokenList;
 function getBlockTimestamp() internal view returns (uint) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }

 // Stake tokens to swap for rewards at actual time and lock it up to delay ends
    function depositSwap(uint256 amount) public {
        require( (block.number>=startBlock && enableDeposits) || amount==0 );
        uint256 _amount = amount;
        UserInfo storage user = userInfo[msg.sender];


       uint256 pending = 0;

        if (user.amount > 0 && user.rewardAmount >0) {

              pending = user.slimiesPerBlock.mul(block.number.sub(user.lastRewardBlock)); //pending to pay

             user.lastRewardBlock=block.number;

              if(pending>user.rewardAmount)
                 pending=user.rewardAmount;

              user.rewardAmount = user.rewardAmount.sub(pending); //update remaining amount to pay
              user.amountV2 = user.amountV2.add(pending);  //update total slimeV2 payed


               if(pending > 0) {
                    totalV2Minted = totalV2Minted.add(pending);
                    slimeV2.mint(address(this), pending);
                    payRefFees(pending);
                    safeStransfer(slimeV2,msg.sender, pending);
                    emit RewardPaid(msg.sender, pending);
                }

                //on finish
                if(user.rewardAmount==0)
                {
                    actualV2PerBlock = actualV2PerBlock.sub(user.slimiesPerBlock);
                }


        }

        if(_amount > 0) {

           _amount = deflacionaryDeposit(slimeV1,_amount);

            totalDeposited = totalDeposited.add(_amount);

            uint256 rewardAmount = _amount.mul(swapRate).mul(vestingBonus).div(1e20); // total v2

            uint256 vestingReward = rewardAmount.mul(vestignRate).div(100); // to vesting and farm + bonus vesting (75%)

            uint256 payActualReward = rewardAmount.sub(vestingReward); // to inmediate pay

            if(payActualReward>0)
            {
               totalV2Minted = totalV2Minted.add(payActualReward);
               slimeV2.mint(msg.sender, payActualReward);
               safeStransfer(slimeV2,msg.sender, payActualReward);
               emit Swap(msg.sender, _amount,payActualReward);
            }


            safeStransfer(slimeV1,dead,_amount);

            user.amount = user.amount.add(_amount);
            user.amountV2 = user.amountV2.add(payActualReward);
            user.lastDeposit = block.number;
            user.lastRewardBlock=block.number;
            user.rewardUpTo = user.lastDeposit.add(vestingPeriod);
            user.rewardAmount = user.rewardAmount.add(vestingReward);
            uint256 previousUserRate = user.slimiesPerBlock;
            user.slimiesPerBlock = user.rewardAmount.div(user.rewardUpTo.sub(user.lastDeposit));

            actualV2PerBlock = actualV2PerBlock.sub(previousUserRate).add(user.slimiesPerBlock);

        }


        emit Deposit(msg.sender, _amount);
    }




    // View function to see pending tokens on frontend.
    function pendingReward(  address _user)   external view returns (uint256) {

        UserInfo storage user = userInfo [_user];
        uint256  pending=0;

        if (block.number > user.lastRewardBlock  ) {

              pending = user.slimiesPerBlock.mul(block.number.sub(user.lastRewardBlock));

             if(pending>user.rewardAmount)
                pending=user.rewardAmount;
        }
        return pending;
    }



    function deflacionaryDeposit(IBEP20 token ,uint256 _amount)  internal returns(uint256)
    {

        uint256 balanceBeforeDeposit = token.balanceOf(address(this));
        token.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 balanceAfterDeposit = token.balanceOf(address(this));
        _amount = balanceAfterDeposit.sub(balanceBeforeDeposit);

        return _amount;
    }



    function payRefFees( uint256 pending ) internal
    {
        uint256 toReferral = pending.mul(fees[0]).div(1000);

        address referrer = address(0);
        if (rewardReferral != address(0)) {
            referrer = SlimeFriends(rewardReferral).getSlimeFriend (msg.sender);

        }

        if (referrer != address(0)) { // send commission to referrer
            slimeV2.mint(referrer, toReferral);
            emit ReferralPaid(msg.sender, referrer,toReferral);
        }
    }



    function safeStransfer(BEP20 token,address _to, uint256 _amount) internal {
        uint256 sbal = token.balanceOf(address(this));
        if (_amount > sbal) {
            token.transfer(_to, sbal);
        } else {
            token.transfer(_to, _amount);
        }
    }

    function updateSwapRate(uint256 newRate) external onlyOwner
    {
        emit  UpdateSwapRate(swapRate,newRate);
        swapRate=newRate;
    }

    function updateEnableDeposits(bool status) external onlyOwner
    {

        enableDeposits=status;
        emit  EnableDeposit(status);
    }
}