/**
 * @title SlimeToken V2
 */


pragma solidity 0.6.12;

import './SafeMath.sol';
import './IBEP20.sol';
import './BEP20Token.sol';


interface DeflationController{
    function checkDeflation(address origin,address caller,address from,address recipient, uint256 amount) external view returns (uint256) ;
}

// SLIMEV2
contract SlimeTokenV2 is BEP20('Slime V2', 'SLIME') {
  using SafeMath for uint256;

   mapping (address => bool ) public minters;

   address public deflationController;

   event SetMinter(address indexed _address,bool status);
   event SetDeflationController(address indexed _addresss);
   event EmergencyBEP20Drain(address token , address owner, uint256 amount);

   constructor() public
   {
     minters[owner()]= true;
   }

   modifier onlyMinter(address _address) {
        require(minters[_address] == true, "Slime: No minter allowed");
        _;
    }

    function mint(uint256 amount) public override onlyOwner returns (bool) {
        _mint(_msgSender(), amount);
     }

    function mint(address _to, uint256 _amount) public onlyMinter(msg.sender) {
        _mint(_to, _amount);
     }


    function transfer(address recipient, uint256 amount) public  override returns (bool) {
         uint256 toBurn = 0;

        if(address(0)!=deflationController && amount>0)
            toBurn = DeflationController(deflationController).checkDeflation(tx.origin,_msgSender(), _msgSender(), recipient, amount);

         if(toBurn>0 && toBurn<amount)
         {
             amount = amount.sub(toBurn);
             _burn(_msgSender(),toBurn);
         }

        _transfer(_msgSender(), recipient, amount);
         return true;
    }

    function setMinter(address _address,bool status) external onlyOwner {

        minters[_address] = status;
        emit SetMinter(_address,status);
    }

    function setDeflationController(address _address ) external onlyOwner {

        deflationController = _address;
    }

    /**
     * @dev See {BEP20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {BEP20};
     *
     * Requirements:
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for `sender`'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public  override returns (bool) {
          uint256 toBurn = 0;

         if(address(0)!=deflationController && amount>0)
          toBurn = DeflationController(deflationController).checkDeflation(tx.origin,_msgSender(),sender, recipient, amount);

         if(toBurn>0 && toBurn<amount)
         {
             amount = amount.sub(toBurn);
             _burn(sender,toBurn);
         }

        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
             allowance(sender,_msgSender()).sub(amount, 'BEP20: transfer amount exceeds allowance')
        );
        return true;
    }

    // owner can drain tokens that are sent here by mistake
    function emergencyBEP20Drain(BEP20 token, uint amount) external onlyOwner {
        emit EmergencyBEP20Drain(address(token), owner(), amount);
        token.transfer(owner(), amount);
    }
}
