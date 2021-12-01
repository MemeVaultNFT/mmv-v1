pragma solidity >=0.4.21 <0.9.0;
pragma experimental ABIEncoderV2;

import "../NFT/nf-token-metadata.sol";

//Token
contract mmvToken is MMVT {
    
    constructor() public {
        //MMV Token specs
        symbol = "MMV";
        name = "MeMeVault Token";
        decimals = 18;
        _totalSupply = 23*10**18;  //initial supply of 23 tokens
        balances[msg.sender] = _totalSupply;  
        
        emit Transfer(address(0), msg.sender, _totalSupply);
    }
    
}

//NFT
contract mmvNFT is NFTokenMetadata {

    constructor() public {
        //MMV NFT specs
        nftName = "MMV Vault Key";
        nftSymbol = "MMVK";
    }
    
    function mintNft(address _receiver, uint _tokenId, string memory _tokenURI) external returns (uint256) {
        require(hasAdmin(), 'Not admin');
        _mint(_receiver, _tokenId);
        _setTokenUri(_tokenId, _tokenURI);

        return _tokenId;
    }
    
    function transferNFT(address _to, uint256 _tokenId) external {
         require(hasAdmin(), 'Not minter');
        _transfer(_to, _tokenId);
    }
    
}

//Staked Token
contract smmvToken is MMVT {
    
    constructor() public {
        //MMV Token specs
        symbol = "sMMV";
        name = "Staked MMV";
        decimals = 18;
        _totalSupply = 23*10**18;  //initial supply of 23 tokens
        balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }
    
}

//Treasury
contract mmvTreasury is Ownable, SafeMath, AccessControl, ReentrancyGuard {

    function getBalance() public view returns (uint){
        address contractAddress = address(this);
        uint256 etherBalance = contractAddress.balance;
        
        return etherBalance;
    }
    
    function withdraw(uint _amount, address _to) onlyAdmin() public nonReentrant returns (bool) {
        address contractAddress = address(this);
        uint256 etherBalance = contractAddress.balance;
        require(etherBalance > 0);
        
        (bool success,  ) = _to.call{value: _amount}("");
        
        return success;
    }

    receive() external payable {}
}

//Mint & Vault
contract vaultMMV is Ownable, SafeMath, AccessControl {
    string[] private allHashes;
    address[] private memeOwners;
    
    uint constant private mult = 10**18;
    uint constant private ratingBurnRate = 999990000000000000;
    uint constant private vaultBurnRate = 988888888888890000;
    
    uint private vaultReward;
    uint private ratingReward;
    uint private memeCount;
    uint private ratingCount;
    
    struct Meme {
        string hash;
        address owner;
        uint reward;
        uint vaultNum; 
        string hLink;
        string timeStamp;
        bool tokensMinted;
        bool keyGranted;
        string meta;
        uint rating;
        uint totalRatings;
        uint price;
    }
    
    struct Rating {
        uint vaultNum;
        address rater;
        uint rating;
        uint reward;
        string timeStamp;
        bool tokensMinted;
    }
    
    mapping (string => Meme) memeIds;
    mapping (uint => mapping(address => Rating)) ratings;
    
    mmvToken token;
    mmvNFT key;
    stakeMMV stake;
    mmvTreasury treasury;
    address _owner;
    
    constructor(mmvToken _token, mmvNFT _key, stakeMMV _stake, mmvTreasury _treasury) public {
        //Token Specs
        token = _token;
        
        //NFT specs
        key = _key;
        
        //Stake address
        stake = _stake;

        //Treasury
        treasury = _treasury;
        
        //Vault variables
        vaultReward = 230000 * mult;  //initial reward for minting
        ratingReward = 23 * mult;  //inital reward for rating
        memeCount = 0;
        ratingCount = 0;
        _owner = msg.sender;

        
     }
     
     //Events
     event memeSent(uint _reward, uint v_Num, string timeStamp, bool divPaid);
     event tokenMint(uint reward);
     event keyGrant(uint _id, string _metaHash);
     event RatingUpdated(uint _vaultNum, uint _averageRating);
     
     function submitMeme(string memory _hash, string memory _timeStamp) public payable {
        require(msg.value == 0.0023 ether);
        require(checkHash(_hash));  //No duplicate
        
        if(memeCount < 230){       //Spread the wealth!
            uint[] memory _checkOwner = checkOwner(msg.sender);
            require(_checkOwner[0] == 0);
        }
        
        uint _Reward = addMeme(_hash, _timeStamp, msg.sender);
        uint vaultNumber = memeIds[_hash].vaultNum;
        uint fee = msg.value;
        
        uint divRate = stake.getDividendRate();
        
        bool paid = false;
        if(divRate > 0){
            uint dividend = safeDiv(safeMul(fee, divRate), 100);
            paid = payDividends(dividend, fee);
        }
        
        emit memeSent(_Reward, vaultNumber, _timeStamp, paid);
     }
     
     function checkHash(string memory _hash) private view returns (bool) {
        bool result = true;
        if(memeCount > 0){
            for(uint i = 0; i < allHashes.length; i++){
                 if(keccak256(bytes(allHashes[i])) == keccak256(bytes(_hash))){
                     result = false;
                     break;
                 }
            }
        }
        return result;
     }
     
     function checkOwner(address _Owner) private view returns (uint[] memory) {
        uint[] memory result = new uint[] (2);
       
        for(uint i = 0; i < memeCount; i++){
             if(memeOwners[i] == _Owner){
                 result[0] = 1;
                 result[1] = i;
                 break;
             }
        }
        return result;
     }
     
     function addMeme(string memory _hash, string memory _timeStamp, address _creator) private returns (uint) {
        
        uint userReward;
        uint vNum;
        string memory _hLink;
        string memory _pre = "ipfs://";
        
        allHashes.push(_hash); //Save to allHashes
        uint[] memory _checkOwner = checkOwner(_creator);
        
        if(_checkOwner[0] < 1){
            memeOwners.push(_creator);
        }
        
        userReward = vaultRewardCalc();  //calculate reward
        
        vNum = allHashes.length;    //Get vault num
        
        _hLink = append(_pre, _hash);         //get ipfs link
        
        memeIds[_hash] = Meme({
              hash: _hash,
              owner: _creator,
              reward: userReward,
              vaultNum: vNum,
              hLink: _hLink,
              timeStamp: _timeStamp,
              tokensMinted: false,
              keyGranted: false,
              meta: "",
              rating: 0,
              totalRatings: 0,
              price: 0
          });
          
       return memeIds[_hash].reward;   
    }
    
    function vaultRewardCalc() private returns (uint) {
       uint _reward;
       
        if(memeCount > 0){
            vaultReward = safeMul((safeDiv(vaultReward, mult)),vaultBurnRate);
            _reward = vaultReward;
            memeCount++;
        }else{
             _reward = vaultReward;
             memeCount++;
        }   
        
        return _reward;
    }
    
    function mintReward(string memory _hash, address _to) public payable {
        require(msg.value == 0.0023 ether);
        require(_to == memeIds[_hash].owner);
        require(!memeIds[_hash].tokensMinted);
        
        uint userbal;
        address addr = _to;
         
        uint _reward = memeIds[_hash].reward;
        
        uint fee = msg.value;
        uint divRate = stake.getDividendRate();
        
        if(divRate > 0){
            uint dividend = safeDiv(safeMul(fee, divRate), 100);
            payDividends(dividend, fee);
        }
        
        memeIds[_hash].tokensMinted = true;
        mintToken(addr, _reward);
        
        userbal = token.balanceOf(addr);
        emit tokenMint(userbal);
    
     }
     
     function grantKey(string memory _hash, string memory _cid) public payable{
        require(msg.sender == memeIds[_hash].owner);
        require(msg.value == 0.0023 ether);
        require(!memeIds[_hash].keyGranted);
         
        address addr;
        uint vNum;
        string memory _uri = "";
        string memory _pre = "ipfs://";
         
        addr = msg.sender;
        vNum = memeIds[_hash].vaultNum;
        _uri = append(_pre, _cid);
         
        memeIds[_hash].keyGranted = true;
        memeIds[_hash].meta = _uri;
        mintKey(addr, vNum, _uri);
        
        uint fee = msg.value;
        uint divRate = stake.getDividendRate();
        
        if(divRate > 0){
            uint dividend = safeDiv(safeMul(fee, divRate), 100);
            payDividends(dividend, fee);
        }
        
        emit keyGrant(vNum, _uri);
        
     }
    
    function mintKey(address _to, uint256 _tokenId, string memory _uri) private {
        key.mintNft(_to, _tokenId, _uri);
    }
      
    function mintToken(address _mintTo, uint _mintAmount) private {
        token.mintTo(_mintTo, _mintAmount);
    }
     
    function append(string memory _prefix, string memory _hash) internal pure returns (string memory) {
        return string(abi.encodePacked(_prefix, _hash));
    }
    
    function submitRating(string memory _hash, uint _rating, string memory _timeStamp) public {
        require(msg.sender != memeIds[_hash].owner);
        uint vaultNum = memeIds[_hash].vaultNum;
        require(!ratings[vaultNum][msg.sender].tokensMinted);
        
        uint rReward = ratingRewardCalc();
        
        ratings[vaultNum][msg.sender] = Rating({
              vaultNum: vaultNum,
              rater: msg.sender,
              rating: _rating,
              reward: rReward,
              timeStamp: _timeStamp,
              tokensMinted: false
          });
          
        updateRating(_hash,_rating);
        
        ratings[vaultNum][msg.sender].tokensMinted = true;
        
        mintToken(msg.sender, rReward);
        
        emit RatingUpdated(vaultNum, memeIds[_hash].rating);
     }
     
    function ratingRewardCalc() private returns (uint) {
        uint _reward;
       
        if(ratingCount > 0){
            ratingReward = safeMul(safeDiv(ratingReward, mult), ratingBurnRate);
            _reward = ratingReward;
            ratingCount++;
        }else{
             _reward = ratingReward;
             ratingCount++;
        }   
        
        return _reward;
        
    }
    
    function updateRating(string memory _hash, uint _rating) private {
        uint avgRating = memeIds[_hash].rating;
        uint totalRatings = memeIds[_hash].totalRatings;
        
        uint sumRatings = safeMul(avgRating, totalRatings);
        
        sumRatings = safeAdd(sumRatings, _rating);
        totalRatings = totalRatings + 1;
        
        avgRating = safeDiv(sumRatings, totalRatings);
        
        memeIds[_hash].rating = avgRating;
        memeIds[_hash].totalRatings = totalRatings;
    }
    
    function vaultTransfer(address _newOwner, address _currentOwner, uint _vaultNum) external onlyAdmin() {
        require(_newOwner != address(0));
        require(_newOwner != _currentOwner);
        uint _index = _vaultNum - 1;
        
        string memory _hash = allHashes[_index]; //get hash of sold vault
        
        memeIds[_hash].owner = _newOwner;  //change ownership
        
        string[] memory _userHashes = getUserHashes(_currentOwner);
        
        if(keccak256(bytes(_userHashes[0])) == keccak256(bytes('no hashes'))){
            uint[] memory _result = checkOwner(_currentOwner);
            delete memeOwners[_result[1]];
        }
    }
    
    function updatePrice(uint _tokenId, uint _price) external onlyAdmin() {
        uint memeIndex = _tokenId - 1;
        
        string memory memeHash = allHashes[memeIndex];
        
        memeIds[memeHash].price = _price;
    }
    
    function payDividends(uint _amount, uint _fee) private returns (bool) {
        uint leftover = safeSub(_fee, _amount);
        
        address payable target = payable(address(stake));
        address payable bank = payable(address(treasury));
        
        (bool success,  ) = target.call{value: _amount}("");        //Transfer to Stake
        bool dist = stake.distribute(_amount);                     //Update claimable amount
        
        (bool remain,  ) = bank.call{value: leftover}("");        //Transfer leftover to Treasury
        
        return success;
    }
    
    
    function getAllHashes() public view returns (string[] memory) {
         return allHashes;
    }
    
    function getUserHashes(address _user) public view returns (string[] memory) {
        
        string[] memory userHashes = new string[] (1);
        
       if(allHashes.length > 0){
          
            uint _count = 0;
    
            for (uint i = 0; i < allHashes.length; i++) {
              
              string memory t_hash = allHashes[i]; //store current hash
              
              address t_user = memeIds[t_hash].owner;  //store current address
              
              if (t_user == _user) {
                userHashes[_count] = t_hash;
                _count++;
                return userHashes;
              }
            }
            
            if(_count == 0){
               userHashes[0] = 'no hashes';
            }
            
        }else{
            
             userHashes[0] = 'no hashes';
        }
    
        return userHashes; 

    }
        
    function getMemeDetail(string memory _hash) public view returns ( 
        address owner,
        uint reward,
        uint vaultNum, 
        string memory hLink,
        string memory timeStamp,
        bool tokensMinted,
        bool keyGranted,
        string memory meta,
        uint rating,
        uint price
        )
        {
        
        Meme memory detail = memeIds[_hash];
        
        return (detail.owner, detail.reward, detail.vaultNum, detail.hLink, detail.timeStamp, detail.tokensMinted, detail.keyGranted, detail.meta, detail.rating, detail.price);    
    }
    
    function getMemes(string memory _hash) public view returns (
        string[] memory hashes,
        address[] memory owners,
        uint[] memory rewards,
        uint[] memory vaultNums, 
        string[] memory timeStamps,
        uint[] memory mRatings,
        uint[] memory prices
        )
        {

        hashes = new string[] (memeCount);
        owners = new address[] (memeCount);
        rewards = new uint[] (memeCount);
        vaultNums = new uint[] (memeCount);
        timeStamps = new string[] (memeCount);
        mRatings = new uint[] (memeCount);
        prices = new uint[] (memeCount);
        
        for (uint i = 0; i < memeCount; i++){
            string memory t_hash = allHashes[i]; 
            
            if(keccak256(bytes(_hash)) != keccak256(bytes("all"))){ //one vault
                
                if(keccak256(bytes(t_hash)) == keccak256(bytes(_hash))){
                    
                    hashes[i] = t_hash;
                    owners[i] = memeIds[t_hash].owner;
                    rewards[i] = memeIds[t_hash].reward;
                    vaultNums[i] = memeIds[t_hash].vaultNum;
                    timeStamps[i] = memeIds[t_hash].timeStamp;
                    mRatings[i] = memeIds[t_hash].rating;
                    prices[i] = memeIds[t_hash].price;
                    break;
                }
            }else{ //grab all memes from all vaults
                
                hashes[i] = t_hash;
                owners[i] = memeIds[t_hash].owner;
                rewards[i] = memeIds[t_hash].reward;
                vaultNums[i] = memeIds[t_hash].vaultNum;
                timeStamps[i] = memeIds[t_hash].timeStamp;
                mRatings[i] = memeIds[t_hash].rating;
                prices[i] = memeIds[t_hash].price;
            }
            
        }
        
        return (hashes, owners, rewards, vaultNums, timeStamps, mRatings, prices);
    }
    
    function getUserRating(uint _vaultNum, address _user) public view returns (uint){
        
        return ratings[_vaultNum][_user].rating; 
    }
    
    function getVaultReward() public view returns (uint){
        return vaultReward;
    }
    
    function getRatingReward() public view returns (uint){
        return ratingReward;
    }
    
    function getMemeCount() public view returns (uint){
        return memeCount;
    }
    
    function getBalance() public view returns (uint){
        address contractAddress = address(this);
        uint256 etherBalance = contractAddress.balance;
        
        return etherBalance;
    }
    
    receive() external payable {}
}


//MMV Offer
contract offerMMV is Ownable, SafeMath, AccessControl, ReentrancyGuard {

    uint private saleCount;
    uint private totalSales;
    uint private commission;
    
    struct Offer {
        address seller;
        address buyer;
        uint offerPrice;
        string timeStamp;
        bool active;
    }
    
    struct Sale {
        uint vaultNum;
        address buyer;
        address seller;
        uint price;
        uint priceUSD;
        string timeStamp;
    }
    
    mapping (uint => Offer) tokenIdOffer;
    mapping (uint => Sale) sales;
    
    mmvToken token;
    mmvNFT key;
    vaultMMV meme;
    stakeMMV stake;
    mmvTreasury treasury;
    address _owner;
    
    constructor(mmvNFT _key, stakeMMV _stake, vaultMMV _meme, mmvTreasury _treasury) public {
        //NFT specs
        key = _key;
        
        //Vault address
        meme = _meme;
        
        //Stake address
        stake = _stake;

        //Treasury
        treasury = _treasury;
        
        //Offer variables
        saleCount = 0;
        
        commission = 5;
        
        _owner = msg.sender;
     }
     
     //Events
     event nftSent(string keyID);
     event NewOffer(uint _offerPrice, address _buyer);
     event AcceptOffer(uint _offerPrice, uint _offerPriceUSD, string _transDate);
     event CancelOffer(uint _offerPrice, address _buyer);
     event VaultTransfer(address _newOwner, uint _vaultNum);
    
    function newOffer(uint256 _tokenId, string memory _timeStamp, address _seller) public nonReentrant() payable {
        require(_seller != msg.sender);
        Offer memory currOffer = tokenIdOffer[_tokenId]; //current Offer
        uint newOfferPrice = msg.value;  //new offer
        require(newOfferPrice > currOffer.offerPrice);
        
        if(currOffer.offerPrice > 0){
            
            address buyer = currOffer.buyer;
            uint price = currOffer.offerPrice;
            
            (bool success,  ) = buyer.call{value: price}("");
            delete tokenIdOffer[_tokenId];
            
            saveOffer(_tokenId, msg.sender, _seller, newOfferPrice, _timeStamp);
        }else{
            saveOffer(_tokenId, msg.sender, _seller, newOfferPrice, _timeStamp);
        }
        
        meme.updatePrice(_tokenId,newOfferPrice);
        
        emit NewOffer(newOfferPrice, msg.sender);
    }
    
    function saveOffer(uint256 _tokenId, address _buyer, address _seller, uint256 _offerPrice, string memory _timeStamp) private {
        
        Offer memory _offer = Offer({
            buyer: _buyer,
            seller: _seller,
            offerPrice: _offerPrice,
            timeStamp: _timeStamp,
            active: true
       
        });
        
        tokenIdOffer[_tokenId] = _offer; //save new offer
    }

    function acceptOffer(uint _tokenId, uint _priceUSD, string memory _transDate) public returns (bool) {
        Offer memory _offer = tokenIdOffer[_tokenId]; //load current offer
        require(_offer.seller != address(0));
        require(msg.sender == _offer.seller);
        require(_offer.active == true);
        
        address seller = _offer.seller;
        address buyer = _offer.buyer;
        uint price = _offer.offerPrice;
        uint proceeds = 0;
           
        uint platformFee = safeDiv(safeMul(price, commission), 100);
        proceeds = price - platformFee;
        
        tokenIdOffer[_tokenId].active = false;
        (bool success, ) = seller.call{value: proceeds}(""); //transfer proceeds to seller
        bool paid = false;
        
        meme.updatePrice(_tokenId, price);
        
        if(success){
            key.transferNFT(buyer, _tokenId);  //transfer vault key
            
            meme.vaultTransfer(buyer,seller,_tokenId);  // transfer vault ownership
                 
            delete tokenIdOffer[_tokenId]; //remove offer
            
            addSale(_tokenId, seller, buyer, price, _priceUSD, _transDate);
        
            uint divRate = stake.getDividendRate();
            if(divRate > 0){
                uint dividend = safeDiv(safeMul(platformFee, divRate), 100);
                paid = payDividends(dividend, platformFee);
            }
        }
            
        emit AcceptOffer(price, _priceUSD, _transDate);
        emit VaultTransfer(buyer,_tokenId);
        
        return paid;
    }
    
    function addSale(uint _tokenId, address _seller, address _buyer, uint _price, uint _priceUSD, string memory _timeStamp) private {
        
        Sale memory _sale = Sale({
            vaultNum: _tokenId,
            buyer: _buyer,
            seller: _seller,
            price: _price,
            priceUSD: _priceUSD,
            timeStamp: _timeStamp
        });
        
        sales[saleCount] = _sale;
        saleCount++;
        totalSales = totalSales + _price;
    }
    
    function cancelOffer(uint _tokenId) public returns (bool) {
        Offer memory _offer = tokenIdOffer[_tokenId];
        require(_offer.buyer == msg.sender);
        require(_offer.active == true);
       
        delete tokenIdOffer[_tokenId];
        
        address buyer = _offer.buyer;
        uint price = _offer.offerPrice;
        
        (bool success,  ) = buyer.call{value: price}("");
        
        emit CancelOffer(price, msg.sender);
        
        return success;
    }
    
    function getOffer(uint _tokenId) public view returns ( 
        address seller,
        address buyer,
        uint offerPrice,
        string memory timeStamp,
        bool active
        )
        {
        
        Offer memory detail = tokenIdOffer[_tokenId];
        
        return (detail.seller, detail.buyer, detail.offerPrice, detail.timeStamp, detail.active);    
    }
    
    function getSales(uint _tokenId) public view returns (
        uint[] memory vaultNums,
        string[] memory transDates,
        address[] memory buyers,
        address[] memory sellers,
        uint[] memory prices,
        uint[] memory USDprices
        )
        {
        
        vaultNums = new uint[] (saleCount);
        transDates = new string[] (saleCount);
        buyers = new address[] (saleCount);
        sellers = new address[] (saleCount);
        prices = new uint[] (saleCount);
        USDprices = new uint[] (saleCount);
        
        for (uint i = 0; i < saleCount; i++){
            
            if(_tokenId != 0){ //one vault
                uint sCount = 0;
                if(sales[i].vaultNum == _tokenId){
                    
                    vaultNums[i] = sales[i].vaultNum;
                    transDates[i] = sales[i].timeStamp;
                    buyers[i] = sales[i].buyer;
                    sellers[i] = sales[i].seller;
                    prices[i] = sales[i].price;
                    USDprices[i] = sales[i].priceUSD;
                    
                    sCount++;
                }
            }else{ //grab all sales from all vaults
                
                vaultNums[i] = sales[i].vaultNum;
                transDates[i] = sales[i].timeStamp;
                buyers[i] = sales[i].buyer;
                sellers[i] = sales[i].seller;
                prices[i] = sales[i].price;
                USDprices[i] = sales[i].priceUSD;
            }
            
        }
        
        return (vaultNums, transDates, buyers, sellers, prices, USDprices);
    }
    
    function payDividends(uint _amount, uint _fee) private returns (bool) {
        
        uint leftover = safeSub(_fee, _amount);
        
        address payable target = payable(address(stake));
        address payable bank = payable(address(treasury));
        
        (bool success,  ) = target.call{value: _amount}("");        //Transfer to Stake
        bool dist = stake.distribute(_amount);                     //Update claimable amount
        
        (bool remain,  ) = bank.call{value: leftover}("");        //Transfer leftover to Treasury
        
        return success;
    }
    
    function getTotalSales() public view returns (uint){
        return totalSales;
    }
    
    function getSalesCount() public view returns (uint){
        return saleCount;
    }
    
    function getBalance() public view returns (uint){
        address contractAddress = address(this);
        uint256 etherBalance = contractAddress.balance;
        
        return etherBalance;
    }
    
    function updateCommission(uint _newFee) public onlyOwner() {
        commission = _newFee;
    }
    
    function getCommissionFee() public view returns (uint) {
        return commission;
    }
    
    receive() external payable {}
}

//Stake Contract
contract stakeMMV is Ownable, SafeMath, AccessControl, ReentrancyGuard {
    //using SafeMath for uint;
    
    uint BIGNUMBER = 10**18;
    uint DECIMAL = 10**3;

    struct stakingInfo {
        uint totalStaked;
        uint sReward;
        uint releaseDate;
    }
    
    uint private dividendRate;
    uint private totalDividend;
    uint private undistributedDiv;
    uint private unclaimedDiv;
    uint private rewardPerToken;
    uint private tokenTotalStaked;
    uint private sTokenTotalMinted;
    uint private totalStakers;
    bool private divPaid;
    
    //allowed token addresses
    mapping (address => stakingInfo) stakeMap; //user to stake amount
    mapping (uint => address) stakers;
    mapping (address => address) Mediator;

    mmvToken token;
    smmvToken sToken;
    
    constructor(mmvToken _token, smmvToken _sToken) public{
        token = _token;  //MMV Token
        sToken = _sToken;  //Staked MMV Token
        totalDividend = 0;
        tokenTotalStaked = 0;
        undistributedDiv = 0;
        unclaimedDiv = 0;
        totalStakers = 0;
        sTokenTotalMinted = 0;
        dividendRate = 0;
    }

    /*
    * @dev stake a specific amount to a token
    * @param _amount the amount to be staked
    * @param to the token the user wish to stake on
    * for demo purposes, not requiring user to actually send in tokens right now
    */
    event Staked(uint _amount);
    
    function stake(uint _amount) external returns (bool) {
        require(_amount != 0);
       
        bool stakerExist = false;
        
        for(uint i = 0; i < totalStakers; i++){  //find staker by address
            if(msg.sender == stakers[i]){
                stakerExist = true;
                break;
            }
        }
        
        if(stakerExist){  //if staker exist
            if (stakeMap[msg.sender].totalStaked == 0){  //user has no stake yet
                stakeMap[msg.sender].totalStaked = _amount;
            }else{
                stakeMap[msg.sender].totalStaked = safeAdd(stakeMap[msg.sender].totalStaked, _amount);
            }
        }else{ //if not add to stakers
            stakers[totalStakers] = msg.sender;
            stakeMap[msg.sender].totalStaked = _amount;
            totalStakers++;
        }
        
        address stakeAddr = address(this);
        
        token.transferFrom(msg.sender, stakeAddr, _amount);
        tokenTotalStaked = safeAdd(tokenTotalStaked, _amount);
        
        mintStakeToken(msg.sender, _amount);
        sTokenTotalMinted = safeAdd(sTokenTotalMinted, _amount);
        
        updateDividendRate(); 
       
        emit Staked(_amount);
       
        return true;
    }
    
    
    /*
    * @dev pay out dividends to stakers, update how much per token each staker can claim
    * @param _reward the aggregate amount to be send to all stakers
    * @param to the token that this dividend gets paid out in
    */
    function distribute(uint _reward) external onlyAdmin() returns (bool){
        require(_reward > 0);
        
        totalDividend = safeAdd(totalDividend, _reward);
        unclaimedDiv = safeAdd(unclaimedDiv, _reward);
        
        if(tokenTotalStaked > 0){
            undistributedDiv = safeAdd(undistributedDiv, _reward);
            rewardPerToken = safeDiv(safeMul(undistributedDiv, BIGNUMBER), tokenTotalStaked);
            
            for(uint i = 0; i < totalStakers; i++){
                
                address sAddr = stakers[i];
                
                if(stakeMap[sAddr].totalStaked > 0){
                    uint newReward = safeDiv(safeMul(rewardPerToken, stakeMap[sAddr].totalStaked), BIGNUMBER);
                    
                    stakeMap[sAddr].sReward = safeAdd(stakeMap[sAddr].sReward, newReward);
                    
                    undistributedDiv = safeSub(undistributedDiv, newReward);  //should go to zero
                }
            }
            
            return true;
        }else{
            undistributedDiv = undistributedDiv + _reward;
            
            return false;
        }
    }
    
    event claimed(uint amount, address receiver);
    /*
    * @dev claim dividends for a particular token that user has stake in
    * @param to the token that the claim is made on
    * @param _receiver the address which the claim is paid to
    */
    
    function claim(uint _amount) external nonReentrant() returns (bool) {
        require(_amount > 0);
        require(stakeMap[msg.sender].sReward > 0);
        require(stakeMap[msg.sender].sReward >= _amount);
        
        address receiver = msg.sender;
       
        (bool success,  ) = receiver.call{value: _amount}("");  //send ETH
        
        if(success){
            unclaimedDiv = safeSub(unclaimedDiv, _amount); //sub totalDividend
            stakeMap[msg.sender].sReward = safeSub(stakeMap[msg.sender].sReward, _amount);
        }
        emit claimed(_amount, receiver);
        return success;
    }
    
    /**
    * @dev finalize withdraw of stake
    */
    function unstake(uint _amount) external nonReentrant() returns (bool) {
        require(stakeMap[msg.sender].totalStaked >= _amount);
        require(sToken.balanceOf(msg.sender) >= _amount);
        
        stakeMap[msg.sender].totalStaked = safeSub(stakeMap[msg.sender].totalStaked,_amount);
        tokenTotalStaked = safeSub(tokenTotalStaked,_amount);
        
        burnStakeToken(msg.sender,_amount);
        
        require(token.transfer(msg.sender,_amount));
        
        updateDividendRate();
        
        return true;
    }
    
    function updateDividendRate() private {
        uint currentSupply = token.totalSupply();
        
        dividendRate = safeDiv(safeMul(tokenTotalStaked,100), currentSupply);
    }
    
    function mintStakeToken(address _to, uint _amount) private {
         sToken.mintTo(_to, _amount);
    }
    
    function burnStakeToken(address _from, uint _amount) private {
         sToken.burnFrom(_from, _amount);
    }
    
    function getDividendRate() public view returns (uint){
        return dividendRate;
    }
    
    function getDividendsPaid() public view returns (uint){
        return totalDividend;
    }
    
    function getUserDividend() public view returns (uint){
        return stakeMap[msg.sender].sReward;
    }
    
    function getUserStake() public view returns (uint){
        return stakeMap[msg.sender].totalStaked;
    }
    
    function getTotalTokensStaked() public view returns (uint){
        return tokenTotalStaked;
    }
    
    function getTotalStakers() public view returns (uint){
        return totalStakers;
    }
    
    function getUndistDiv() public view returns (uint){
        return undistributedDiv;
    }
    
    function getUnclaimedDiv() public view returns (uint){
        return unclaimedDiv;
    }
    
    function getBalance() public view returns (uint){
        address contractAddress = address(this);
        uint256 etherBalance = contractAddress.balance;
        
        return etherBalance;
    }
    
    receive() external payable {}
}
