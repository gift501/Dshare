// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DShareStorage is Ownable {
    using Strings for uint256;

    /* Constants and Configuration */
    uint256 public constant MAX_STORAGE_1GB_BYTES     = 1 * 1024 * 1024 * 1024; // 1 GB
    uint256 public constant MAX_STORAGE_5GB_BYTES     = 5 * 1024 * 1024 * 1024; // 5 GB
    uint256 public constant UPGRADE_TO_5GB_PRICE       = 0.1 ether;

    uint256 public constant SHARE_FEE                  = 10_000_000_000_000;      // 0.00001 ETH
    uint256 public constant MIN_DOWNLOAD_PRICE         = 10_000_000_000_000;      // 0.00001 ETH
    uint256 public constant MAX_DOWNLOAD_PRICE         = 0.01 ether;
    uint256 public constant OWNER_DOWNLOAD_FEE_PERCENT = 20;                    // 20 %

    uint256 public constant UPLOAD_POINTS  = 3;
    uint256 public constant SHARE_POINTS   = 10;
    uint256 public constant DOWNLOAD_POINTS= 20;
    uint256 public constant REFERRAL_POINTS= 1000;

    uint256 public constant MAX_SINGLE_UPLOAD_1GB_BYTES= 300 * 1024 * 1024;      // 300 MB
    uint256 public constant MAX_SINGLE_UPLOAD_5GB_BYTES= 600 * 1024 * 1024;      // 600 MB
    uint256 public constant MAX_SINGLE_SHARE_1GB_BYTES = 300 * 1024 * 1024;      // 300 MB
    uint256 public constant MAX_SINGLE_SHARE_5GB_BYTES = 600 * 1024 * 1024;      // 600 MB
    uint256 public constant MAX_SHARE_POINTS_THRESHOLD = 200 * 1024 * 1024;      // <= 200 MB => 10 pts

    /* Referral Window */
    uint256 public constant REFERRAL_WINDOW = 48 hours;  // claim window after registration

    /* Data Structures */
    struct File {
        string  name;
        string  ipfsHash;
        string  fileType;
        uint256 size;
        address uploader;
        uint256 uploadTime;
        bool    isPublic;
        uint256 downloadPrice;
    }

    /* State Variables */
    mapping(address => File[])   public userFiles;
    mapping(string  => File)     public filesByHash;
    mapping(address => uint256)  public userStorageUsed;
    mapping(address => uint256)  public userStorageLimit;
    mapping(address => uint256)  public userPoints;
    mapping(address => uint256)  public userBalances;

    // Global public file registry
    File[] public _publicFiles;
    mapping(string => uint256) _publicIdx; // ipfsHash => index in _publicFiles array

    /* Profile & Referral Data */
    mapping(address => string)   public profileCID;
    mapping(address => uint256)  public registeredAt;
    mapping(address => bool)     public referralRedeemed;

    mapping(address => string)   public userReferralCode;
    mapping(string  => address)  public referralCodeToUser;
    mapping(address => uint256)  public userReferralCount;
    mapping(address => bool)     public isRegistered;

    uint256 private _referralCodeSalt = 0;

    /* Events */
    event Deposited             (address indexed user, uint256 amount);
    event Withdrawn             (address indexed user, uint256 amount);
    event StorageLimitUpgraded  (address indexed user, uint256 newLimit, uint256 pricePaid);

    event FileUploaded          (address indexed uploader, string indexed ipfsHash, string name, uint256 size, uint256 pointsEarned);
    event FileShared            (address indexed sender, address indexed receiver, string indexed ipfsHash, uint256 feePaid, uint256 pointsEarned);
    event FileVisibilityChanged (string indexed ipfsHash, bool isPublic, uint256 newPrice);
    event FilePurchased         (string indexed ipfsHash, address indexed purchaser, address indexed uploader, uint256 amountPaid, uint256 pointsEarned);
    event FileDeleted           (address indexed deleter, string indexed ipfsHash, uint256 sizeFreed);
    event PublicFileAdded       (string indexed ipfsHash);
    event PublicFileRemoved     (string indexed ipfsHash);

    event PointsEarned          (address indexed user, uint256 points, string reason);
    event FeeCollected          (address indexed collector, uint256 amount, string feeType);

    /* Referral-related events */
    event UserRegistered        (address indexed newUser, string profileCID);
    event ReferralCodeGenerated (address indexed user, string code);
    event ReferralCountUpdated  (address indexed referrer, uint256 newCount);
    event PointsLeaderboardUpdate(address indexed user, uint256 totalPoints);

    /* Constructor */
    constructor() Ownable(msg.sender) {}

    /* Fallbacks */
    receive() external payable {
        _deposit();
    }
    fallback() external payable {
        _deposit();
    }
    function _deposit() internal {
        require(isRegistered[msg.sender], "Register first");
        userBalances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /* Modifiers */
    modifier validHash(string memory cid) {
        require(bytes(cid).length > 0, "Empty hash");
        _;
    }
    modifier onlyUploader(string memory cid) {
        require(filesByHash[cid].uploader == msg.sender, "Not uploader");
        _;
    }

    /*===================================================================*/

    /* User Management Functions */

    function registerUser(string calldata _profileCID) external {
        require(!isRegistered[msg.sender], "Already registered");
        isRegistered[msg.sender]    = true;
        profileCID[msg.sender]      = _profileCID;
        registeredAt[msg.sender]    = block.timestamp;
        userStorageLimit[msg.sender]= MAX_STORAGE_1GB_BYTES;

        emit UserRegistered(msg.sender, _profileCID);
    }

    function redeemReferral(string calldata _code) external {
        require(isRegistered[msg.sender], "Register first");
        require(!referralRedeemed[msg.sender], "Referral already used");
        require(block.timestamp <= registeredAt[msg.sender] + REFERRAL_WINDOW, "Window closed");

        address referrer = referralCodeToUser[_code];
        require(referrer != address(0), "Invalid code");
        require(referrer != msg.sender, "Self-referral not allowed");

        referralRedeemed[msg.sender] = true;

        userPoints[msg.sender] += REFERRAL_POINTS;
        emit PointsEarned(msg.sender, REFERRAL_POINTS, "Referral (Referred)");
        emit PointsLeaderboardUpdate(msg.sender, userPoints[msg.sender]);

        userPoints[referrer] += REFERRAL_POINTS;
        emit PointsEarned(referrer, REFERRAL_POINTS, "Referral (Referrer)");
        emit PointsLeaderboardUpdate(referrer, userPoints[referrer]);

        userReferralCount[referrer] += 1;
        emit ReferralCountUpdated(referrer, userReferralCount[referrer]);
    }

    function generateReferralCode() external returns (string memory) {
        require(isRegistered[msg.sender], "Register first");
        require(bytes(userReferralCode[msg.sender]).length == 0, "Already have code");

        string memory code;
        for (uint8 i; i < 10; i++) {
            uint256 seed = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        msg.sender,
                        block.prevrandao,
                        block.number,
                        _referralCodeSalt++
                    )
                )
            );
            uint256 num = seed % 10_000_000; // 7-digit code
            code = num.toString();
            while (bytes(code).length < 7) code = string(abi.encodePacked("0", code));
            if (referralCodeToUser[code] == address(0)) break;
            if (i == 9) revert("Could not generate unique code");
        }

        userReferralCode[msg.sender] = code;
        referralCodeToUser[code]     = msg.sender;
        emit ReferralCodeGenerated(msg.sender, code);
        return code;
    }

    /* Financial Functions */

    function deposit() external payable { _deposit(); }

    function withdraw(uint256 amount) external {
        require(isRegistered[msg.sender], "Register first");
        require(amount > 0 && userBalances[msg.sender] >= amount, "Insufficient");
        userBalances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getUserBalance() external view returns (uint256) {
        return userBalances[msg.sender];
    }

    function upgradeStorage() external {
        require(isRegistered[msg.sender], "Register first");
        require(userStorageLimit[msg.sender] == MAX_STORAGE_1GB_BYTES, "Already 5 GB");
        require(userBalances[msg.sender] >= UPGRADE_TO_5GB_PRICE, "Balance too low");

        userBalances[msg.sender] -= UPGRADE_TO_5GB_PRICE;
        userStorageLimit[msg.sender] = MAX_STORAGE_5GB_BYTES;
        emit StorageLimitUpgraded(msg.sender, MAX_STORAGE_5GB_BYTES, UPGRADE_TO_5GB_PRICE);
    }

    /* File Management Functions */

    function uploadFile(
        string calldata name,
        string calldata cid,
        string calldata fileType,
        uint256 size
    ) external validHash(cid) {
        require(isRegistered[msg.sender], "Register first");
        require(filesByHash[cid].uploader == address(0), "CID exists");

        uint256 limit = userStorageLimit[msg.sender];
        require(userStorageUsed[msg.sender] + size <= limit, "Quota exceeded");

        if (limit == MAX_STORAGE_1GB_BYTES)
            require(size <= MAX_SINGLE_UPLOAD_1GB_BYTES, "> 300 MB on 1 GB plan");
        else
            require(size <= MAX_SINGLE_UPLOAD_5GB_BYTES, "> 600 MB on 5 GB plan");

        filesByHash[cid] = File({
            name: name,
            ipfsHash: cid,
            fileType: fileType,
            size: size,
            uploader: msg.sender,
            uploadTime: block.timestamp,
            isPublic: false,
            downloadPrice: 0
        });
        userFiles[msg.sender].push(filesByHash[cid]);
        userStorageUsed[msg.sender] += size;

        userPoints[msg.sender] += UPLOAD_POINTS;
        emit PointsLeaderboardUpdate(msg.sender, userPoints[msg.sender]);
        emit FileUploaded(msg.sender, cid, name, size, UPLOAD_POINTS);
        emit PointsEarned(msg.sender, UPLOAD_POINTS, "File Upload");
    }

    function shareFile(string calldata cid, address receiver)
        external
        validHash(cid)
        onlyUploader(cid)
    {
        require(isRegistered[msg.sender], "Register first");
        require(isRegistered[receiver], "Receiver not registered");
        require(receiver != msg.sender && receiver != address(0), "Bad receiver");
        require(userBalances[msg.sender] >= SHARE_FEE, "Balance too low");

        File storage f = filesByHash[cid];

        uint256 planLimit = userStorageLimit[msg.sender];
        require(
            f.size <= (
                planLimit == MAX_STORAGE_1GB_BYTES ? MAX_SINGLE_SHARE_1GB_BYTES : MAX_SINGLE_SHARE_5GB_BYTES
            ),
            "Share size limit"
        );

        userBalances[msg.sender] -= SHARE_FEE;
        userBalances[owner()]    += SHARE_FEE;
        emit FeeCollected(owner(), SHARE_FEE, "Share Fee");

        require(userStorageUsed[receiver] + f.size <= userStorageLimit[receiver], "Receiver quota exceeded");

        bool exists;
        for (uint i; i < userFiles[receiver].length; i++)
            if (keccak256(bytes(userFiles[receiver][i].ipfsHash)) == keccak256(bytes(cid))) { exists = true; break; }
        if (!exists) {
            userFiles[receiver].push(f);
            userStorageUsed[receiver] += f.size;
        }

        uint256 pts = f.size <= MAX_SHARE_POINTS_THRESHOLD ? SHARE_POINTS : 0;
        if (pts > 0) {
            userPoints[msg.sender] += pts;
            emit PointsLeaderboardUpdate(msg.sender, userPoints[msg.sender]);
        }

        emit FileShared(msg.sender, receiver, cid, SHARE_FEE, pts);
        if (pts > 0) emit PointsEarned(msg.sender, pts, "File Share");
    }

    function setFileVisibilityAndPrice(string calldata cid, bool pub, uint256 price)
        external
        validHash(cid)
        onlyUploader(cid)
    {
        require(price >= MIN_DOWNLOAD_PRICE && price <= MAX_DOWNLOAD_PRICE, "Price out of range");
        File storage f = filesByHash[cid];
        
        bool wasPublic = f.isPublic;
        
        f.isPublic      = pub;
        f.downloadPrice = price;

        if (pub && !wasPublic) {
            _addPublicFile(cid);
        } else if (!pub && wasPublic) {
            _removePublicFile(cid);
        }
        
        emit FileVisibilityChanged(cid, pub, price);
    }

    function purchaseFile(string calldata cid) external validHash(cid) {
        require(isRegistered[msg.sender], "Register first");
        File storage f = filesByHash[cid];
        require(f.uploader != address(0) && f.isPublic, "Unavailable");
        require(msg.sender != f.uploader, "Cannot buy own file");
        require(isRegistered[f.uploader], "Uploader not registered");

        uint256 cost = f.downloadPrice;
        require(userBalances[msg.sender] >= cost, "Balance too low");

        uint256 ownerCut    = (cost * OWNER_DOWNLOAD_FEE_PERCENT) / 100;
        uint256 uploaderCut = cost - ownerCut;

        userBalances[msg.sender] -= cost;
        userBalances[owner()]    += ownerCut;
        userBalances[f.uploader] += uploaderCut;
        emit FeeCollected(owner(), ownerCut, "Download Fee");

        require(userStorageUsed[msg.sender] + f.size <= userStorageLimit[msg.sender], "Quota exceeded");
        bool exists;
        for (uint i; i < userFiles[msg.sender].length; i++)
            if (keccak256(bytes(userFiles[msg.sender][i].ipfsHash)) == keccak256(bytes(cid))) { exists = true; break; }
        if (!exists) {
            userFiles[msg.sender].push(f);
            userStorageUsed[msg.sender] += f.size;
        }

        userPoints[msg.sender] += DOWNLOAD_POINTS;
        emit PointsLeaderboardUpdate(msg.sender, userPoints[msg.sender]);

        emit FilePurchased(cid, msg.sender, f.uploader, cost, DOWNLOAD_POINTS);
        emit PointsEarned(msg.sender, DOWNLOAD_POINTS, "File Download");
    }

    function deleteFile(string calldata cid)
        external
        validHash(cid)
        onlyUploader(cid)
    {
        File storage f = filesByHash[cid];
        uint256 sz = f.size;
        bool wasPublic = f.isPublic;

        // If the file was public, remove it from the public registry
        if (wasPublic) {
            _removePublicFile(cid);
        }

        delete filesByHash[cid];

        for (uint i; i < userFiles[msg.sender].length; i++) {
            if (keccak256(bytes(userFiles[msg.sender][i].ipfsHash)) == keccak256(bytes(cid))) {
                if (i < userFiles[msg.sender].length - 1)
                    userFiles[msg.sender][i] = userFiles[msg.sender][userFiles[msg.sender].length - 1];
                userFiles[msg.sender].pop();
                break;
            }
        }

        userStorageUsed[msg.sender] -= sz;
        emit FileDeleted(msg.sender, cid, sz);
    }

    /* Internal Functions for Public Registry Management */
    function _addPublicFile(string memory cid) internal {
        bool foundInPublic = false;
        uint256 existingIdx = _publicIdx[cid];
        if (existingIdx > 0 || (_publicFiles.length > 0 && keccak256(bytes(_publicFiles[0].ipfsHash)) == keccak256(bytes(cid)))) {
            if (existingIdx < _publicFiles.length && keccak256(bytes(_publicFiles[existingIdx].ipfsHash)) == keccak256(bytes(cid))) {
                 foundInPublic = true;
            }
        }

        if (!foundInPublic) {
            _publicFiles.push(filesByHash[cid]);
            _publicIdx[cid] = _publicFiles.length - 1;
            emit PublicFileAdded(cid);
        }
    }

    function _removePublicFile(string memory cid) internal {
        uint256 index = _publicIdx[cid];
        if (index < _publicFiles.length && keccak256(bytes(_publicFiles[index].ipfsHash)) == keccak256(bytes(cid))) {
            if (index != _publicFiles.length - 1) {
                File storage lastFile = _publicFiles[_publicFiles.length - 1];
                _publicFiles[index] = lastFile;
                _publicIdx[lastFile.ipfsHash] = index;
            }
            _publicFiles.pop();
            delete _publicIdx[cid];
            emit PublicFileRemoved(cid);
        }
    }

    /* View Functions */
    function getMyFiles() external view returns (File[] memory) { return userFiles[msg.sender]; }

    function getFileByHash(string calldata cid)
        external
        view
        validHash(cid)
        returns (string memory, string memory, uint256, address, uint256, bool, uint256)
    {
        File storage f = filesByHash[cid];
        require(f.uploader != address(0), "Not found");
        return (f.name, f.fileType, f.size, f.uploader, f.uploadTime, f.isPublic, f.downloadPrice);
    }

    function getUserStorageInfo(address u) external view returns (uint256 used, uint256 limit) {
        return (userStorageUsed[u], userStorageLimit[u]);
    }

    function getMyPoints() external view returns (uint256) { return userPoints[msg.sender]; }

    function getAllPublicFiles(uint256 offset, uint256 limit, string calldata fileTypeFilter)
        external
        view
        returns (File[] memory)
    {
        uint256 totalFilteredCount = 0;
        for (uint256 i = 0; i < _publicFiles.length; i++) {
            if (bytes(fileTypeFilter).length == 0 || keccak256(bytes(_publicFiles[i].fileType)) == keccak256(bytes(fileTypeFilter))) {
                totalFilteredCount++;
            }
        }

        uint256 startIndex = offset;
        if (startIndex >= totalFilteredCount) {
            return new File[](0);
        }

        uint256 endIndex = startIndex + limit;
        if (endIndex > totalFilteredCount) {
            endIndex = totalFilteredCount;
        }

        uint256 numFilesToReturn = endIndex - startIndex;
        File[] memory publicFiles = new File[](numFilesToReturn);
        uint256 publicFilesIndex = 0;
        uint256 currentFilteredCount = 0;

        for (uint256 i = 0; i < _publicFiles.length; i++) {
            if (bytes(fileTypeFilter).length == 0 || keccak256(bytes(_publicFiles[i].fileType)) == keccak256(bytes(fileTypeFilter))) {
                if (currentFilteredCount >= startIndex && publicFilesIndex < numFilesToReturn) {
                    publicFiles[publicFilesIndex] = _publicFiles[i];
                    publicFilesIndex++;
                }
                currentFilteredCount++;
            }
            if (publicFilesIndex == numFilesToReturn) {
                break;
            }
        }
        return publicFiles;
    }

    function getMyFilesAndPublic(uint256 offset, uint256 limit, string calldata fileTypeFilter)
        external
        view
        returns (File[] memory myFiles, File[] memory publicFiles)
    {
        myFiles = this.getMyFiles();
        publicFiles = this.getAllPublicFiles(offset, limit, fileTypeFilter);
    }

    /* Owner Functions */
    function withdrawContractFees(uint256 amount) external onlyOwner {
        require(amount > 0 && address(this).balance >= amount, "Invalid amount");
        payable(owner()).transfer(amount);
    }
}