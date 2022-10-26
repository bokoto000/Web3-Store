// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./Errors.sol";

library Pagination {
    function getPagination(
        uint256 _length,
        uint256 _pageSize,
        uint256 _pageNumber
    )
        internal
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 pages = _length / _pageSize;
        uint256 lastPage = _length - pages * _pageSize > 0 ? 1 : 0;
        uint256 pagesCount = pages + lastPage;
        if (_pageNumber > pagesCount) revert PageOutOfRange();
        uint256 end = _pageNumber * (_pageSize) < _length
            ? _pageNumber * (_pageSize)
            : _length;
        uint256 start = _pageSize * (_pageNumber - 1);
        return (start, end, pagesCount);
    }
}
