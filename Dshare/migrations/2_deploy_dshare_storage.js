const DShareStorage = artifacts.require("DShareStorage");

module.exports = function (deployer) {
  deployer.deploy(DShareStorage);
};