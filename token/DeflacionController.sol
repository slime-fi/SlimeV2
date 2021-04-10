/**
 * @title DeflationController
 * @dev Implements rules for token burn
 */
pragma solidity 0.6.12;

import '../libs/SafeMath.sol';
import '../libs/BEP20.sol';


//SlimeDeflationController for SlimeV2
contract DeflationController is Ownable {
    using SafeMath for uint256;

   uint256 public eoaFee = 20; // default burn for EOA  0.2%

   uint256 public defFee = 50; // default burn for nonEOA 0.5%

   uint256 constant public MAX_DEFLATION_ALLOWED = 750; // 7.5%

   event SetRule(address indexed _address,uint256 _senderFee,uint256 _callerFee,uint256 _recipientFee);
   event SetRuleStatus(address indexed _address,bool _status);
   event EmergencyBEP20Drain(address token , address owner, uint256 amount);
   event SetEoaFee(uint256 eoaFee);
   event SetDefFee(uint256 defFee);


   //Static deflation rule
   struct DeflationRule {
        uint256 senderFee;
        uint256 callerFee;
        uint256 recipientFee;
        bool active;
    }

   mapping (address => DeflationRule ) public rules;

    /**
     * Check burn amount following DeflationRule, returns how much amount will be burned
     *
     * */
  function checkDeflation(address origin,address caller,address _from,address recipient, uint256 amount) external view returns (uint256){

        uint256 burnAmount = 0;

        DeflationRule memory fromRule = rules[_from];
        DeflationRule memory callerRule = rules[caller];
        DeflationRule memory recipientRule = rules[recipient];

        //check transfers and transferFrom to/from caller but not fransferfrom to diferent recipient
        if(callerRule.active && callerRule.callerFee>0){
            //default caller rule fee
                 burnAmount = burnAmount.add(amount.mul(callerRule.callerFee).div(10000));
        }

         // check transfer/TransferFrom from any caller to a selected recipient
        if(recipientRule.active && recipientRule.recipientFee>0){
                burnAmount = burnAmount.add(amount.mul(recipientRule.recipientFee).div(10000));
        }

        // check fr0m fee from a selected from
        if(fromRule.active && fromRule.senderFee>0){
                burnAmount = burnAmount.add(amount.mul(fromRule.senderFee).div(10000));
        }

        //normal transfer and transferFrom from eoa (called directly)
        if( burnAmount==0 && origin==caller && eoaFee>0 && !callerRule.active && !recipientRule.active && !fromRule.active)
        {
            burnAmount = burnAmount.add(amount.mul(eoaFee).div(10000));

        //no burn because no rules on that tx, setUp default burn
        }else if(burnAmount==0 && origin!=caller &&    defFee>0 && !callerRule.active && !recipientRule.active && !fromRule.active)
        {
            burnAmount = burnAmount.add(amount.mul(defFee).div(10000));
        }


        return burnAmount;
    }

    function setRule(address _address,uint256 _senderFee,uint256 _callerFee,uint256 _recipientFee,bool _active) external onlyOwner
    {
        require(_senderFee<=MAX_DEFLATION_ALLOWED && _callerFee<=MAX_DEFLATION_ALLOWED && _recipientFee <= MAX_DEFLATION_ALLOWED );
         rules[_address] = DeflationRule({
             senderFee : _senderFee,
             callerFee:_callerFee,
             recipientFee:_recipientFee,
             active : _active
        });

        emit SetRule(_address,_senderFee,_callerFee,_recipientFee);
        emit SetRuleStatus(_address,_active);
    }

    function setRuleStatus(address _address,bool _active)  external onlyOwner
    {
         rules[_address].active=_active;

         emit SetRuleStatus(_address,_active);

    }


   function setEoaFee(uint256 _eoaFee) external onlyOwner
   {
        require(_eoaFee<=MAX_DEFLATION_ALLOWED);
        eoaFee = _eoaFee;
        emit SetEoaFee(_eoaFee);
   }

    function setDefFee(uint256 _defFee) external onlyOwner
   {
       require(_defFee<=MAX_DEFLATION_ALLOWED);
        defFee = _defFee;
        emit SetDefFee(_defFee);
   }

    // owner can drain tokens that are sent here by mistake
    function emergencyBEP20Drain(BEP20 token, uint amount) external onlyOwner {
        emit EmergencyBEP20Drain(address(token), owner(), amount);
        token.transfer(owner(), amount);
    }
}