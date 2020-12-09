// SPDX-License-Identifier: WTFPL
pragma solidity ^0.6.12;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ProteinToken.sol";

// ProteinMaster is the hub that accumulates and distributes PROT
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once PROT is sufficiently
// distributed and the community can show to govern itself.
//
contract ProteinMaster is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. PROTs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that PROTs distribution occurs.
        uint256 accProteinPerShare; // Accumulated PROTs per share, times 1e12. See below.
    }

    // The PROT TOKEN!
    ProteinToken public protein;
    // Dev address.
    address public devaddr;
    address public devaddrtwo;
    address public devaddrthree;
    address public devaddrfour;
    address public devaddrfive;
    // Our healthy private farmers addresses supporting the proyect

    // Block number when bonus PROT period ends.
    uint256 public bonusEndBlock;
    // PROT tokens created per block.
    uint256 public proteinPerBlock;
    // Bonus muliplier for early protein makers.
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
    // The block number when PROT mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    modifier validatePool(uint256 _pid) {
        require(_pid < poolInfo.length, "validatePool: pool exists?");
        _;
    }

    constructor(
        ProteinToken _protein,
        address _devaddr,
        address _devaddrtwo,
        address _devaddrthree,
        address _devaddrfour,
        address _devaddrfive,
        uint256 _proteinPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        bool _privateFarm
    ) public {
        protein = _protein;
        devaddr = _devaddr;
        devaddrtwo = _devaddrtwo;
        devaddrthree = _devaddrthree;
        devaddrfour = _devaddrfour;
        devaddrfive = _devaddrfive;
        proteinPerBlock = _proteinPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
        privateFarm = _privateFarm;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function changeProtPerBlock(uint256 _newProteinPerBlock) public onlyOwner {
        proteinPerBlock = _newProteinPerBlock;
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
            accProteinPerShare: 0
        }));
    }

    // Update the given pool's PROT allocation point. Can only be called by the owner.
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

    // View function to see pending PROTs on frontend.
    function pendingProt(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accProteinPerShare = pool.accProteinPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 proteinReward = multiplier.mul(proteinPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accProteinPerShare = accProteinPerShare.add(proteinReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accProteinPerShare).div(1e12).sub(user.rewardDebt);
    }	

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() internal {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) internal validatePool(_pid) {
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
        uint256 proteinReward = multiplier.mul(proteinPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        protein.mint(devaddr, proteinReward.div(DEV_SHARES));
        protein.mint(devaddrtwo, proteinReward.div(DEV_SHARES));
        protein.mint(devaddrthree, proteinReward.div(DEV_SHARES));
        protein.mint(devaddrfour, proteinReward.div(DEV_SHARES));
        protein.mint(devaddrfive, proteinReward.div(DEV_SHARES));
        protein.mint(address(this), proteinReward);
        pool.accProteinPerShare = pool.accProteinPerShare.add(proteinReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to ProteinMaster for PROT allocation. Conditioned by privateFarming bool
    function deposit(uint256 _pid, uint256 _amount) public validatePool(_pid) {
        if(!privateFarm){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accProteinPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeProtTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accProteinPerShare).div(1e12);        
        emit Deposit(msg.sender, _pid, _amount);
        }

        //for dev test previous oficial launch, we need to test without worries in the mainet
        if(privateFarm){
        require(msg.sender == devaddr || msg.sender == devaddrtwo || msg.sender == devaddrthree || msg.sender == devaddrfour || msg.sender == devaddrfive ,"Your address is not a dev, please await for public farming");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accProteinPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeProtTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accProteinPerShare).div(1e12);        
        emit Deposit(msg.sender, _pid, _amount);
        

        }


    }

    // Withdraw LP tokens from ProteinMaster.
    function withdraw(uint256 _pid, uint256 _amount) public validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accProteinPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeProtTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accProteinPerShare).div(1e12);
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

    // Safe protein transfer function, just in case if rounding error causes pool to not have enough PROTs.
    function safeProtTransfer(address _to, uint256 _amount) internal {
        uint256 proteinBal = protein.balanceOf(address(this));
        if (_amount > proteinBal) {
            protein.transfer(_to, proteinBal);
        } else {
            protein.transfer(_to, _amount);
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
