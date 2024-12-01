import { ethers } from "hardhat";

import type { IncoEventContract } from "../../types";
import { getSigners } from "../signers";


export async function deployConfidentialERC1155(): Promise<IncoEventContract> {
  const signers = await getSigners();

  const erc1155ContractFactory = await ethers.getContractFactory("IncoEventContract");
  const erc1155Contract = await erc1155ContractFactory.connect(signers.alice).deploy("0xc02C45cf15832791D12f41fCA2920a314bE51df5");

  return erc1155Contract;
}
