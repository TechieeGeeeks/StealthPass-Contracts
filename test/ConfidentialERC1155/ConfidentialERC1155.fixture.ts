import { ethers } from "hardhat";

import type { IncoEventContract } from "../../types";
import { getSigners } from "../signers";


export async function deployConfidentialERC1155(): Promise<IncoEventContract> {
  const signers = await getSigners();

  const erc1155ContractFactory = await ethers.getContractFactory("IncoEventContract");
  const erc1155Contract = await erc1155ContractFactory.connect(signers.alice).deploy("0x275C42c018E70f993734F1D200f474A97Af9Ff8E");

  return erc1155Contract;
}
