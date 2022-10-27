// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import {Ownable} from "./Ownable.sol";
import "./Errors.sol";

import {Pagination} from "./Utils.sol";

contract Store is Ownable {
    struct Product {
        string serial;
        string name;
        string description;
        uint32 price;
        uint32 quantity;
    }

    mapping(uint32 => Product) private products;
    mapping(string => bool) private insertedProducts;
    uint32[] private productKeys;
    uint32[] private productKeysLocation;
    uint32 private availableProductsCount;

    mapping(uint32 => address[]) private clientShopped;
    mapping(uint32 => mapping(address => bool)) private insertedClientShopped;

    struct OwnedInfo {
        bool owned;
        uint256 blockNumber;
    }
    mapping(address => mapping(uint32 => OwnedInfo)) private ownerOf;
    uint32 constant ReturnWindow = 100;

    struct WithdrawTransaction {
        uint256 amount;
        uint256 blockNumber;
        bool status;
        bool cancelled;
    }

    WithdrawTransaction[] withdrawals;
    uint32 constant withdrawalWindow = 200;

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

    modifier productIdExist(uint32 _productId) {
        if (_productId >= productKeys.length)
            revert ProductDoesntExist(_productId);
        _;
    }

    modifier isOwnerOf(uint32 _productId) {
        if (!ownerOf[msg.sender][_productId].owned) revert ProductIsNotOwned();
        _;
    }

    modifier isNotOwnerOf(uint32 _productId) {
        if (ownerOf[msg.sender][_productId].owned) revert ProductIsOwned();
        _;
    }

    event ProductBought(uint32 indexed productId, address buyer);
    event ProductReturned(uint32 indexed productId, address buyer);

    function _swapProductKeys(uint32 _productKey1, uint32 _productKey2)
        private
    {
        uint32 productLocation = productKeysLocation[_productKey1];
        uint32 swapProductLocation = productKeysLocation[_productKey2];
        productKeys[productLocation] = _productKey2;
        productKeysLocation[_productKey2] = productLocation;
        productKeys[swapProductLocation] = _productKey1;
        productKeysLocation[_productKey1] = swapProductLocation;
    }

    function _makeProductUnavailable(uint32 _productId) private {
        uint32 swapProduct = productKeys[availableProductsCount - 1];
        _swapProductKeys(_productId, swapProduct);
        availableProductsCount--;
    }

    function _makeProductAvailable(uint32 _productId) private {
        uint32 swapProduct = productKeys[availableProductsCount];
        _swapProductKeys(_productId, swapProduct);
        availableProductsCount++;
    }

    function addProduct(
        string calldata _serial,
        string calldata _name,
        string calldata _description,
        uint32 _price,
        uint32 _quantity
    ) external onlyOwner productDoesntExist(_serial) returns (uint32) {
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

        uint32 newId = uint32(productKeys.length);
        products[newId] = newProduct;
        productKeys.push(newId);
        productKeysLocation.push(newId);

        if (_quantity > 0) {
            _makeProductAvailable(newId);
        }
        return uint32(productKeys.length) - 1;
    }

    function addQuantity(uint32 _productId, uint32 _quantity)
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

    function getAvailableProducts(uint32 _pageSize, uint32 _pageNumber)
        external
        view
        returns (Product[] memory, uint32)
    {
        (uint32 start, uint32 end, uint32 pagesCount) = Pagination
            .getPagination(availableProductsCount, _pageSize, _pageNumber);
        Product[] memory availableProducts = new Product[](end - start);
        for (uint32 i = start; i < end; i++) {
            availableProducts[i - start] = products[productKeys[i]];
        }
        return (availableProducts, pagesCount);
    }

    function getProductsInfo(uint32 _productId)
        external
        view
        productIdExist(_productId)
        returns (Product memory)
    {
        return products[_productId];
    }

    function getProductBuyers(
        uint32 _productId,
        uint32 _pageSize,
        uint32 _pageNumber
    )
        external
        view
        productIdExist(_productId)
        returns (address[] memory, uint32)
    {
        address[] storage productBuyers = clientShopped[_productId];
        (uint32 start, uint32 end, uint32 pagesCount) = Pagination
            .getPagination(
                uint32(productBuyers.length),
                _pageSize,
                _pageNumber
            );
        address[] memory buyers = new address[](end - start);
        for (uint32 i = start; i < end; i++) {
            buyers[i - start] = productBuyers[i];
        }
        return (buyers, pagesCount);
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
