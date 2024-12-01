import { expect } from "chai";
import { AbiCoder, AddressLike, Signature } from "ethers";

import { asyncDecrypt, awaitAllDecryptionResults } from "../asyncDecrypt";
import { createInstances } from "../instance";
import { getSigners, initSigners } from "../signers";
import { deployConfidentialERC1155 } from "./ConfidentialERC1155.fixture";

const hre = require("hardhat");

describe("ConfidentialERC1155Example Tests", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    this.instances = await createInstances(this.signers);
    this.ConfidentialERC1155 = await deployConfidentialERC1155();
    this.contractAddress = await this.ConfidentialERC1155.getAddress();
  });

  it("Should be able to Deploy Inco Contract ", async function () {
     console.log(this.contractAddress);
  });
});
