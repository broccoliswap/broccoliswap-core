// SPDX-License-Identifier: WTFPL
pragma solidity >=0.4.22 <0.8.0;

contract Migrations {
  address public owner = msg.sender; //al momento de hacer el deploy, automagicamente me vuelvo el owner
  uint public last_completed_migration;

  modifier restricted() {
    require(
      msg.sender == owner,
      "This function is restricted to the contract's owner"
    );
    _;
  }

  function setCompleted(uint completed) public restricted {
    last_completed_migration = completed;
  }
}
