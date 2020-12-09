// SPDX-License-Identifier: WTFPL
pragma solidity ^0.6.12;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BroccoliToken.sol";

// BroccoliMaster is the hub that accumulates and distributes BROC
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once BROC is sufficiently
// distributed and the community can show to govern itself.
//
contract BroccoliMaster is Ownable {
    using SafeMath for uint256; //Open zeppeling sefe libraries
    using SafeERC20 for IERC20; 

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. BROCs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that BROCs distribution occurs.
        uint256 accBrocPerShare; // Accumulated BROCs per share, times 1e12. See below.
    }

    // The BROC TOKEN!
    BroccoliToken public broc; 
    // Devs addresses
    address public devaddr;
    address public devaddrtwo;
    address public devaddrthree;
    address public devaddrfour;
    address public devaddrfive;
    // Block number when bonus BROC period ends.
    uint256 public bonusEndBlock;
    // BROC tokens created per block.
    uint256 public brocPerBlock;
    // Bonus multiplier for early broc makers.
    uint256 public constant BONUS_MULTIPLIER = 2;
	// dev shares 10.0%
    uint256 public constant DEV_SHARES = 50; //reward / 50 = 2% X 5 Devs Addresses = 10%
	//bool for first hours of private farming
    bool privateFarm;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when BROC mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    modifier validatePool(uint256 _pid) {
        require(_pid < poolInfo.length, "validatePool: pool exists?");
        _;
    }

    constructor(
        BroccoliToken _broc,
        address _devaddr,
        address _devaddrtwo,
        address _devaddrthree,
        address _devaddrfour,
        address _devaddrfive,
        uint256 _brocPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        bool _privateFarm
    ) public {
        broc = _broc;
        devaddr = _devaddr;
        devaddrtwo = _devaddrtwo;
        devaddrthree = _devaddrthree;
        devaddrfour = _devaddrfour;
        devaddrfive = _devaddrfive;
        brocPerBlock = _brocPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
        privateFarm = _privateFarm;
    }

    function poolLength() external view returns (uint256) { //devuelve la cantidad de struct pools
        return poolInfo.length;
    }

    function changeBrocPerBlock(uint256 _newBrocPerBlock) public onlyOwner { //cambia la generacion de broc por block
        brocPerBlock = _newBrocPerBlock;
    }

    // Detects whether the given pool already exists
    function checkPoolDuplicate(IERC20 _lpToken) internal {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: existing pool");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        checkPoolDuplicate(_lpToken);
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accBrocPerShare: 0
        }));
    }

    // Update the given pool's BROC allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner validatePool(_pid) {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock)
            );
        }
    }

    // View function to see staked amount in pool on frontend
    function staked(uint256 _pid, address _user) external view returns(uint256){
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    // View function to see pending BROCs on frontend.
    function pendingBroc(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBrocPerShare = pool.accBrocPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 brocReward = multiplier.mul(brocPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accBrocPerShare = accBrocPerShare.add(brocReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accBrocPerShare).div(1e12).sub(user.rewardDebt); 
    }	

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() internal {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) internal validatePool(_pid) { //en este pool tambien se hace mint al devshare
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 brocReward = multiplier.mul(brocPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        broc.mint(devaddr, brocReward.div(DEV_SHARES));
        broc.mint(devaddrtwo, brocReward.div(DEV_SHARES));
        broc.mint(devaddrthree, brocReward.div(DEV_SHARES));
        broc.mint(devaddrfour, brocReward.div(DEV_SHARES));
        broc.mint(devaddrfive, brocReward.div(DEV_SHARES));
        broc.mint(address(this), brocReward);
        pool.accBrocPerShare = pool.accBrocPerShare.add(brocReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to BroccoliMaster for BROC allocation. Conditioned by privateFarming bool
    function deposit(uint256 _pid, uint256 _amount) public validatePool(_pid) {
        //for dev test previous oficial launch, we need to test without worries in the mainet
        if(privateFarm){
        require(msg.sender == devaddr || msg.sender == devaddrtwo || msg.sender == devaddrthree || msg.sender == devaddrfour || msg.sender == devaddrfive,"Your address is not a dev, please await for public farming");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accBrocPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeBrocTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBrocPerShare).div(1e12);        
        emit Deposit(msg.sender, _pid, _amount);
    }
        if(!privateFarm){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accBrocPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeBrocTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBrocPerShare).div(1e12);        
        emit Deposit(msg.sender, _pid, _amount);
    }
    }

    // Withdraw LP tokens from BroccoliMaster.
    function withdraw(uint256 _pid, uint256 _amount) public validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accBrocPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeBrocTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBrocPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe broc transfer function, just in case if rounding error causes pool to not have enough BROCs.
    function safeBrocTransfer(address _to, uint256 _amount) internal {
        uint256 brocBal = broc.balanceOf(address(this));
        if (_amount > brocBal) {
            broc.transfer(_to, brocBal);
        } else {
            broc.transfer(_to, _amount);
        }
    }

    //Desactivate address restriction for pool deposits, begin public farming
    function setPublicFarming() external onlyOwner{
        privateFarm = false;
    }

    // Update dev address by the previous dev.
    function setDev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: what?");
        devaddr = _devaddr;
    }
    function setDevTwo(address _devaddrtwo) public {
        require(msg.sender == devaddrtwo, "dev: what?");
        devaddrtwo = _devaddrtwo;
    }
    function setDevThree(address _devaddrthree) public {
        require(msg.sender == devaddrthree, "dev: what?");
        devaddrthree = _devaddrthree;
    }
    function setDevFour(address _devaddrfour) public {
        require(msg.sender == devaddrfour, "dev: what?");
        devaddrfour = _devaddrfour;
    }
    function setDevFive(address _devaddrfive) public {
        require(msg.sender == devaddrfive, "dev: what?");
        devaddrfive = _devaddrfive;
    }
}
