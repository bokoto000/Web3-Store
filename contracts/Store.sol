// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import {Ownable} from "./Ownable.sol";
import "./Errors.sol";

contract Store is Ownable {
    struct Product {
        string serial;
        string name;
        string description;
        uint256 price;
        uint256 quantity;
    }

    mapping(uint256 => Product) private products;
    mapping(string => bool) private insertedProducts;
    uint256[] private productKeys;
    uint256[] private productKeysLocation;
    uint256 private availableProductsCount;

    mapping(uint256 => address[]) private clientShopped;
    mapping(uint256 => mapping(address => bool)) private insertedClientShopped;

    struct OwnedInfo {
        bool owned;
        uint256 blockNumber;
    }
    mapping(address => mapping(uint256 => OwnedInfo)) private ownerOf;
    uint256 constant ReturnWindow = 100;

    struct WithdrawTransaction {
        uint256 amount;
        uint256 blockNumber;
        bool status;
        bool cancelled;
    }

    WithdrawTransaction[] withdrawals;
    uint256 constant withdrawalWindow = 200;

    constructor() {
        withdrawals.push(WithdrawTransaction(0, 0, true, false));
        availableProductsCount = 0;
    }

    modifier productExist(string calldata _serial) {
        if (!insertedProducts[_serial]) {
            revert ProductSerialDoesntExist(_serial);
        }
        _;
    }

    modifier productDoesntExist(string calldata _serial) {
        if (insertedProducts[_serial]) revert ProductSerialExist(_serial);
        _;
    }

    modifier productIdExist(uint256 _productId) {
        if (_productId >= productKeys.length)
            revert ProductDoesntExist(_productId);
        _;
    }

    modifier isOwnerOf(uint256 _productId) {
        if (!ownerOf[msg.sender][_productId].owned) revert ProductIsNotOwned();
        _;
    }

    modifier isNotOwnerOf(uint256 _productId) {
        if (ownerOf[msg.sender][_productId].owned) revert ProductIsOwned();
        _;
    }

    event ProductBought(uint256 indexed productId, address buyer);
    event ProductReturned(uint256 indexed productId, address buyer);

    function _swapProductKeys(uint256 _productKey1, uint256 _productKey2) private {
        uint256 productLocation = productKeysLocation[_productKey1];
        uint256 swapProductLocation = productKeysLocation[_productKey2];        
        productKeys[productLocation] = _productKey2;
        productKeysLocation[_productKey2] = productLocation;
        productKeys[swapProductLocation] = _productKey1;
        productKeysLocation[_productKey1] = swapProductLocation;
    }

    function _makeProductUnavailable(uint256 _productId) private {
        uint256 swapProduct = productKeys[availableProductsCount - 1];
        _swapProductKeys(_productId, swapProduct);
        availableProductsCount--;
    }

    function _makeProductAvailable(uint256 _productId) private {
        uint256 swapProduct = productKeys[availableProductsCount];
        _swapProductKeys(_productId, swapProduct);
        availableProductsCount++;
    }

    function addProduct(
        string calldata _serial,
        string calldata _name,
        string calldata _description,
        uint256 _price,
        uint256 _quantity
    ) external onlyOwner productDoesntExist(_serial) returns (uint256) {
        if (bytes(_serial).length == 0) revert SerialIsEmpty();
        if (bytes(_name).length == 0) revert NameIsEmpty();
        if (bytes(_description).length == 0) revert DescriptionIsEmpty();
        Product memory newProduct = Product(
            _serial,
            _name,
            _description,
            _price,
            _quantity
        );
        insertedProducts[_serial] = true;

        uint256 newId = productKeys.length;
        products[productKeys.length] = newProduct;
        productKeys.push(newId);
        productKeysLocation.push(newId);

        if (_quantity > 0) {
            _makeProductAvailable(newId);
        }
        return productKeys.length - 1;
    }

    function addQuantity(uint256 _productId, uint256 _quantity)
        external
        onlyOwner
        productIdExist(_productId)
    {
        Product storage product = products[_productId];
        products[_productId].quantity += _quantity;
        if (product.quantity > 0) _makeProductAvailable(_productId);
    }

    function buyProduct(uint32 _productId)
        external
        payable
        isNotOwnerOf(_productId)
        productIdExist(_productId)
    {
        Product storage product = products[_productId];
        if (product.quantity == 0) revert NoQuantityLeft();
        if (msg.value < product.price) revert NotEnoughETH();

        if (insertedClientShopped[_productId][msg.sender])
            revert ProductBoughtBefore();

        product.quantity--;
        uint256 refund = msg.value - product.price;
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }

        clientShopped[_productId].push(msg.sender);
        insertedClientShopped[_productId][msg.sender] = true;
        OwnedInfo storage newOwner = ownerOf[msg.sender][_productId];
        newOwner.owned = true;
        newOwner.blockNumber = block.number;
        if (product.quantity == 0) _makeProductUnavailable(_productId);
        emit ProductBought(_productId, msg.sender);
    }

    function returnProduct(uint32 _productId)
        external
        payable
        productIdExist(_productId)
        isOwnerOf(_productId)
    {
        Product storage product = products[_productId];
        OwnedInfo storage ownedInfo = ownerOf[msg.sender][_productId];
        if (block.number > ownedInfo.blockNumber + ReturnWindow)
            revert ReturnTimeExpired();
        payable(msg.sender).transfer(product.price);
        product.quantity++;
        ownedInfo.owned = false;
        if (product.quantity == 1) _makeProductAvailable(_productId);
        emit ProductReturned(_productId, msg.sender);
    }

    function getAvailableProducts(uint32 _numberOfProducts, uint32 _offset)
        external
        view
        returns (uint256[] memory, uint256)
    {
        if (_numberOfProducts == 0) revert NumberOfProductsIsZero();
        if (_offset >= availableProductsCount) revert OffsetMoreThanProducts();
        uint256 end = _offset + _numberOfProducts < availableProductsCount
            ? _offset + _numberOfProducts
            : availableProductsCount;
        uint256[] memory productsArr = new uint256[](_numberOfProducts);
        for (uint256 i = _offset; i < end; i++) {
            productsArr[i - _offset] = productKeys[i];
        }
        return (productsArr, end - _offset);
    }

    function getProductsInfo(uint256 _productId)
        external
        view
        returns (Product memory)
    {
        return products[_productId];
    }

    function getProductBuyers(uint256 _productId) external view returns (address[] memory){
        return clientShopped[_productId];
    }

    function getBalance() private view returns (uint256) {
        return address(this).balance;
    }

    function withdrawQueue(uint256 _amount) external onlyOwner {
        uint256 withdrawalsLength = withdrawals.length;
        WithdrawTransaction storage lastWithdraw = withdrawals[
            withdrawalsLength - 1
        ];
        if (
            withdrawals[withdrawalsLength - 1].blockNumber + withdrawalWindow >
            block.number
        ) {
            if (!withdrawals[withdrawalsLength - 1].cancelled)
                revert WithdrawalTooSoon();
        }
        if (lastWithdraw.status == false && lastWithdraw.cancelled == false)
            revert LastWithdrawNotExecuted();
        if (_amount > getBalance()) revert NotEnoughETH();
        withdrawals.push(
            WithdrawTransaction(_amount, block.number, false, false)
        );
    }

    function withdrawExecute() external payable onlyOwner {
        uint256 withdrawalsLength = withdrawals.length;
        uint256 withdrawId = withdrawalsLength - 1;
        WithdrawTransaction storage transaction = withdrawals[withdrawId];
        if (transaction.status == true) revert WithdrawExecuted();
        if (transaction.cancelled == true) revert WithdrawCancelled();
        if (transaction.amount > getBalance()) revert NotEnoughETH();
        if (transaction.blockNumber + withdrawalWindow > block.number)
            revert WithdrawalTooSoon();
        transaction.status = true;
        payable(owner).transfer(transaction.amount);
    }

    function withdrawCancel() external onlyOwner {
        uint256 withdrawalsLength = withdrawals.length;
        uint256 withdrawId = withdrawalsLength - 1;
        WithdrawTransaction storage transaction = withdrawals[withdrawId];
        if (transaction.cancelled == true) revert WithdrawCancelled();
        transaction.cancelled = true;
    }
}
