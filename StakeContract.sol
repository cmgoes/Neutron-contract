// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "hardhat/console.sol";

interface IRewardToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract StakingSystem is Ownable, ERC721Holder {
    IRewardToken public rewardsToken;
    IERC721 public nft1;
    IERC721 public nft2;

    address public token1;
    address public token2;

    uint256 public stakedTotal;
    uint256 public stakingStartTime;
    uint256 constant stakingTime = 180 seconds;
    uint256 constant token = 10e18;
    
    struct Staker {
        mapping(uint256 => address) collections
        mapping(address => uint256[]) tokenIds;
        mapping(address => mapping(uint256 => uint)) tokenStakingCoolDown;
        uint256 balance;
        uint256 rewardsReleased;
    }
/*
    constructor(IERC721 _nft1, IERC721 _nft2, IRewardToken _rewardsToken) {
        nft1 = _nft1;
        nft2 = _nft2;
        rewardsToken = _rewardsToken;
    }
*/
    constructor(address _token1, address _token2, IRewardToken _rewardsToken) {
        token1 = _token1;
        token2 = _token2;
        rewardsToken = _rewardsToken;
    }

    /// @notice mapping of a staker to its wallet
    mapping(address => Staker) public stakers;

    /// @notice Mapping from token ID to owner address

    mapping(address => mapping(uint256 => address)) public tokenOwner;
    bool public tokensClaimable;
    bool initialised;

    /// @notice event emitted when a user has staked a nft

    event Staked(address owner, address collection, uint256 amount);

    /// @notice event emitted when a user has unstaked a nft
    event Unstaked(address owner, address collection, uint256 amount);

    /// @notice event emitted when a user claims reward
    event RewardPaid(address indexed user, uint256 reward);

    /// @notice Allows reward tokens to be claimed
    event ClaimableStatusUpdated(bool status);

    /// @notice Emergency unstake tokens without rewards
    event EmergencyUnstake(address indexed user, address collection, uint256 tokenId);

    function initStaking() public onlyOwner {
        //needs access control
        require(!initialised, "Already initialised");
        stakingStartTime = block.timestamp;
        initialised = true;
    }

    function setTokensClaimable(bool _enabled) public onlyOwner {
        //needs access control
        tokensClaimable = _enabled;
        emit ClaimableStatusUpdated(_enabled);
    }

    function getStakedTokens(address _user, address collection)
        public
        view
        returns (uint256[] memory tokenIds)
    {
        return stakers[_user].tokenIds[collection];
    }

    function stake(address collection, uint256 tokenId) public {
        _stake(msg.sender, collection, tokenId);
    }

    function stakeBatch(address collection, uint256[] memory tokenIds) public {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _stake(msg.sender, collection, tokenIds[i]);
        }
    }

    function _stake(address _user, address collection, uint256 _tokenId) internal {
        require(initialised, "Staking System: the staking has not started");
        require(
            IERC721(collection).ownerOf(_tokenId) == _user,
            "user must be the owner of the token"
        );
        Staker storage staker = stakers[_user];

        staker.tokenIds[collection].push(_tokenId);
        staker.tokenStakingCoolDown[collection][_tokenId] = block.timestamp;
        tokenOwner[collection][_tokenId] = _user;
        IERC721(collection).approve(address(this), _tokenId);
        IERC721(collection).safeTransferFrom(_user, address(this), _tokenId);

        emit Staked(_user, collection, _tokenId);
        stakedTotal++;
    }

    function unstake(address collection, uint256 _tokenId) public {
        claimReward(msg.sender);
        _unstake(msg.sender, collection, _tokenId);
    }

    function unstakeBatch(address collection, uint256[] memory tokenIds) public {
        claimReward(msg.sender);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (tokenOwner[collection][tokenIds[i]] == msg.sender) {
                _unstake(msg.sender, collection, tokenIds[i]);
            }
        }
    }

    // Unstake without caring about rewards. EMERGENCY ONLY.
    function emergencyUnstake(address collection, uint256 _tokenId) public {
        require(
            tokenOwner[collection][_tokenId] == msg.sender,
            "nft._unstake: Sender must have staked tokenID"
        );
        _unstake(msg.sender, collection, _tokenId);
        emit EmergencyUnstake(msg.sender, collection, _tokenId);
    }

    function _unstake(address _user, address collection, uint256 _tokenId) internal {
        require(
            tokenOwner[collection][_tokenId] == _user,
            "Nft Staking System: user must be the owner of the staked nft"
        );
        Staker storage staker = stakers[_user];

        //uint256 lastIndex = staker.tokenIds.length - 1;
        //uint256 lastIndexKey = staker.tokenIds[lastIndex];
        
        if (staker.tokenIds[collection].length > 0) {
            staker.tokenIds[collection].pop();
        }
        staker.tokenStakingCoolDown[collection][_tokenId] = 0;
        delete tokenOwner[collection][_tokenId];

        IERC721(collection).safeTransferFrom(address(this), _user, _tokenId);

        emit Unstaked(_user, collection, _tokenId);
        stakedTotal--;
    }

    function updateReward(address _user) public {
        
        Staker storage staker = stakers[_user];
        uint256[] storage ids = staker.tokenIds;
        for (uint256 i = 0; i < ids.length; i++) {
            if (
                staker.tokenStakingCoolDown[ids[i]] <
                block.timestamp + stakingTime &&
                staker.tokenStakingCoolDown[ids[i]] > 0
            ) {            
                uint256 stakedDays = ((block.timestamp - uint(staker.tokenStakingCoolDown[ids[i]]))) / stakingTime;
                uint256 partialTime = ((block.timestamp - uint(staker.tokenStakingCoolDown[ids[i]]))) % stakingTime;
                
                staker.balance +=  token * stakedDays;
                staker.tokenStakingCoolDown[ids[i]] = block.timestamp - partialTime;                
            }
        }
    }

    function claimReward(address _user) public {
        require(tokensClaimable == true, "Tokens cannnot be claimed yet");

        Staker storage staker = stakers[_user];
        uint256[] storage ids = staker.tokenIds;
        for (uint256 i = 0; i < ids.length; i++) {
            if (
                staker.tokenStakingCoolDown[ids[i]] <
                block.timestamp + stakingTime &&
                staker.tokenStakingCoolDown[ids[i]] > 0
            ) {            
                uint256 stakedDays = ((block.timestamp - uint(staker.tokenStakingCoolDown[ids[i]]))) / stakingTime;
                uint256 partialTime = ((block.timestamp - uint(staker.tokenStakingCoolDown[ids[i]]))) % stakingTime;
                
                staker.balance +=  token * stakedDays;
                staker.tokenStakingCoolDown[ids[i]] = block.timestamp - partialTime;                
            }
        }
        //require(stakers[_user].balance > 0 , "0 rewards yet");


        stakers[_user].rewardsReleased += stakers[_user].balance;
        stakers[_user].balance = 0;
   
        rewardsToken.mint(_user, stakers[_user].balance);

        emit RewardPaid(_user, stakers[_user].balance);
    }
}
