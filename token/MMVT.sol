pragma solidity >=0.4.21 <0.9.0;

import "../security/Ownable.sol";
 
//Safe Math Interface
 
contract SafeMath {
 
    function safeAdd(uint a, uint b) public pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }
 
    function safeSub(uint a, uint b) public pure returns (uint c) {
        require(b <= a);
        c = a - b;
    }
 
    function safeMul(uint a, uint b) public pure returns (uint c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }
 
    function safeDiv(uint a, uint b) public pure returns (uint c) {
        require(b > 0);
        c = a / b;
    }
}
 
 
//ERC Token Standard #20 Interface
 
abstract contract ERC20Interface {
    function totalSupply() public view virtual returns (uint);
    function balanceOf(address tokenOwner) public view virtual returns (uint balance);
    function allowance(address tokenOwner, address spender) public view virtual returns (uint remaining);
    function transfer(address to, uint tokens) public virtual returns (bool success);
    function approve(address spender, uint tokens) public virtual returns (bool success);
    function transferFrom(address from, address to, uint tokens) public virtual returns (bool success);
 
    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}
 
 
//Contract function to receive approval and execute function in one call
 
abstract contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token, bytes memory data) public virtual;
}
 
//Actual token contract
 
contract MMVT is ERC20Interface, SafeMath, Ownable, AccessControl {
    string public symbol;
    string public  name;
    uint8 public decimals;
    uint public _totalSupply;
    uint public _maxSupply;
    uint public _totalTokenHolders;
 
    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowed;
 
    event Mint(address indexed minter, address indexed account, uint256 amount);
    event Burn(address indexed burner, address indexed account, uint256 amount);
    
    constructor() public {
        symbol = "MMVT";
        name = "MMV Token";
        decimals = 18;
        _totalSupply = 23*10**18;  //initial supply of 23 tokens
        _maxSupply = 23000000*10**18;   //Supply max is 2.3M
        balances[msg.sender] = _totalSupply;
        _totalTokenHolders = 1;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }
    
    function totalTokenHolders() public view returns (uint) {
        return _totalTokenHolders;
    }
    
 
    function totalSupply() public view override returns (uint) {
        return _totalSupply  - balances[address(0)];
    }
 
    function balanceOf(address tokenOwner) public view override returns (uint balance) {
        return balances[tokenOwner];
    }
 
    function transfer(address to, uint tokens) public override returns (bool success) {
        balances[msg.sender] = safeSub(balances[msg.sender], tokens);
        balances[to] = safeAdd(balances[to], tokens);
        emit Transfer(msg.sender, to, tokens);
        
        updateTokenHolders(2,to,msg.sender,tokens);
         
        return true;
    }
 
    function approve(address spender, uint tokens) public override returns (bool success) {
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);

        return true;
    }
 
    function transferFrom(address from, address to, uint tokens) public override returns (bool success) {
        balances[from] = safeSub(balances[from], tokens);
        allowed[from][msg.sender] = safeSub(allowed[from][msg.sender], tokens);
        balances[to] = safeAdd(balances[to], tokens);
        emit Transfer(from, to, tokens);
        
        updateTokenHolders(2,to,from,tokens);
        
        return true;
    }
 
    function allowance(address tokenOwner, address spender) public view override returns (uint remaining) {
        return allowed[tokenOwner][spender];
    }
 
    function approveAndCall(address spender, uint tokens, bytes memory data) public returns (bool success) {
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        ApproveAndCallFallBack(spender).receiveApproval(msg.sender, tokens, address(this), data);
        return true;
    }
    
    function increaseApproval(address _spender, uint _addedValue) public returns (bool)
    {
        allowed[msg.sender][_spender] = safeAdd(allowed[msg.sender][_spender], _addedValue);
        
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        
        return true;
    }

    function decreaseApproval(address _spender, uint _subtractedValue) public returns (bool) 
    {
        uint oldValue = allowed[msg.sender][_spender];
        
        if (_subtractedValue > oldValue) {
            allowed[msg.sender][_spender] = 0;
        } else {
            allowed[msg.sender][_spender] = safeSub(oldValue, _subtractedValue);
        }
        
        emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
        
        return true;
   }

    function mintTo(address _to, uint _amount) public 
    {
        require(hasAdmin(), 'Not admin');
        require(_to != address(0), 'ERC20: to address is not valid');
        require(_amount > 0, 'ERC20: amount is not valid');

        _totalSupply = safeAdd(_totalSupply, _amount);
        balances[_to] = safeAdd(balances[_to], _amount);

        emit Mint(msg.sender, _to, _amount);
        
        updateTokenHolders(0, _to, address(0), _amount);
        
    }

    function burnFrom(address _from, uint _amount) public onlyAdmin()
    {
        require(_from != address(0), 'ERC20: from address is not valid');
        require(balances[_from] >= _amount, 'ERC20: insufficient balance');
        
        balances[_from] = safeSub(balances[_from], _amount);
        _totalSupply = safeSub(_totalSupply, _amount);

        emit Burn(msg.sender, _from, _amount);
        
        updateTokenHolders(1, address(0), _from, _amount);
    }
    
    function updateTokenHolders(uint _eventNum, address _to, address _from, uint _amount) private {
        
        if(_eventNum == 0 && balances[_to] == _amount){ //mint new holder
            _totalTokenHolders++;
        }else if(_eventNum == 1 && balances[_from] == 0){ //burn all user tokens
            _totalTokenHolders--;
        }else if(_eventNum == 2 && balances[_to] == _amount && balances[_from] > 0){ //add _to new holder
            _totalTokenHolders++;
        }else if(_eventNum == 2 && balances[_to] > _amount && balances[_from] == 0){ //remove _from as holder
            _totalTokenHolders--;
        }
    }

 
   receive() external payable {}
}
