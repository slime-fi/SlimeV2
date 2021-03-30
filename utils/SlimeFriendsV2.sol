
pragma solidity ^0.6.12;

import '../libs/SafeMath.sol';
import '../libs/BEP20.sol';
import '../libs/SafeBEP20.sol';

interface OldSlimeFriends
{
    function getSlimeFriend(address farmer) external view returns (address);

}

contract SlimeFriendsV2 {
      using SafeBEP20 for IBEP20;


    mapping(address => address) public referrers; // account_address -> referrer_address
    mapping(address => uint256) public referredCount; // referrer_address -> num_of_referred

    event Referral(address indexed referrer, address indexed farmer);
    event NextOwner(address indexed _owner);
    event AdminStatus(address indexed _admin,bool _status);

    // Standard contract ownership transfer.
    address public owner;
    address private nextOwner;

    mapping(address => bool) public isAdmin;

    address public oldSlimeFriend;

    constructor (address _oldSlimeFriend) public {
        oldSlimeFriend =_oldSlimeFriend;
        owner = msg.sender;
    }

    // Standard modifier on methods invokable only by contract owner.
    modifier onlyOwner {
        require(msg.sender == owner, "OnlyOwner methods called by non-owner.");
        _;
    }

    modifier onlyAdmin {
        require(isAdmin[msg.sender], "OnlyAdmin methods called by non-admin.");
        _;
    }

    // Standard contract ownership transfer implementation,
    function approveNextOwner(address _nextOwner) external onlyOwner {
        require(_nextOwner != owner, "Cannot approve current owner.");

        nextOwner = _nextOwner;
        emit NextOwner(nextOwner);
    }

    function acceptNextOwner() external {
        require(msg.sender == nextOwner, "Can only accept preapproved new owner.");
        owner = nextOwner;
    }

    function setSlimeFriend(address farmer, address referrer) external onlyAdmin {


         if(referrers[farmer] == address(0) && oldSlimeFriend!=address(0) && referrer != address(0))
        {
           address oldReferrer = OldSlimeFriends(oldSlimeFriend).getSlimeFriend(farmer);

            if (oldReferrer == address(0) ) {
                referrers[farmer] = oldReferrer;
                referredCount[oldReferrer] += 1;
                emit Referral(oldReferrer, farmer);
            }
        }


        if (referrers[farmer] == address(0) && referrer != address(0)) {
            referrers[farmer] = referrer;
            referredCount[referrer] += 1;
            emit Referral(referrer, farmer);
        }
    }

    function getSlimeFriend(address farmer) external view returns (address) {
        address newReferrer = referrers[farmer];

        if(oldSlimeFriend!=address(0) && newReferrer==address(0))
        {
           return OldSlimeFriends(oldSlimeFriend).getSlimeFriend(farmer);
        }
        return referrers[farmer];
    }

    // Set admin status.
    function setAdminStatus(address _admin, bool _status) external onlyOwner {
        isAdmin[_admin] = _status;

        emit AdminStatus(  _admin,  _status);
    }

    function setSlimeFriendAdmin(address farmer, address referrer) external onlyAdmin {

       referrers[farmer] = referrer;
    }

    event EmergencyBEP20Drain(address token, address owner, uint256 amount);

    // owner can drain tokens that are sent here by mistake
    function emergencyBEP20Drain(BEP20 token, uint amount) external onlyOwner {
        emit EmergencyBEP20Drain(address(token), owner, amount);
        token.transfer(owner, amount);
    }
}
