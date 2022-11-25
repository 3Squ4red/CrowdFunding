const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("CrowdFunding", () => {
  const minContribution = 100;
  const targetAmount = 5000;
  let creator, contributors, contract, getProject;

  async function deployContract() {
    [creator, ...contributors] = await ethers.getSigners();
    const CrowdFunding = await ethers.getContractFactory("CrowdFunding");
    contract = await CrowdFunding.deploy();
    getProject = async () => {
      return await contract.getProjectDetails(creator.address, 0);
    };
  }

  before(async () => {
    await loadFixture(deployContract);
  });

  describe("Creating a project", () => {
    const title = "Social Media";
    const description = "A next-gen social media app";
    it("should revert with invalid inputs while creating a project", async () => {
      await expect(
        contract.createProject("", description, minContribution, targetAmount)
      ).to.revertedWithCustomError(contract, "InvalidTitle");
      await expect(
        contract.createProject(title, "", minContribution, targetAmount)
      ).to.revertedWithCustomError(contract, "InvalidDescription");
      await expect(
        contract.createProject(title, description, 0, targetAmount)
      ).to.revertedWithCustomError(contract, "InvalidMinContribution");
      await expect(
        contract.createProject(title, description, minContribution, 0)
      ).to.revertedWithCustomError(contract, "InvalidTarget");
    });
    it("should successfully create a project", async () => {
      await contract.createProject(
        title,
        description,
        minContribution,
        targetAmount
      );
      const project = await getProject();
      expect(project.title).to.equal(title);
      expect(project.description).to.equal(description);
    });
  });

  describe("Requesting funds", async () => {
    it("should revert if the funds are requested before target is reached", async () => {
      // Requesting funds
      await expect(
        contract.requestFunds(0, 500, contributors[10].address, "dance party")
      ).to.revertedWith("target not met");
    });
  });

  describe("Contributing to a project", () => {
    it("should revert if the project creator contributes", async () => {
      await expect(
        contract.connect(creator).contribute(creator.address, 0)
      ).to.revertedWithCustomError(contract, "SelfContribution");
    });
    it("should revert if the contribution is less than the project's min contribution", async () => {
      await expect(
        contract
          .connect(contributors[0])
          .contribute(creator.address, 0, { value: minContribution - 50 })
      ).to.revertedWithCustomError(contract, "InsufficientContribution");
    });
    it("should successfully contribute to a project", async () => {
      await contract
        .connect(contributors[0])
        .contribute(creator.address, 0, { value: 200 });
      await contract
        .connect(contributors[1])
        .contribute(creator.address, 0, { value: 200 });
      const project = await getProject();
      expect(project.contributions[0].amount).to.equal(200);
      expect(project.contributions[1].amount).to.equal(200);
    });
    it("should return back extra contribution", async () => {
      // 400 already contributed, so on contributing 5000 this time, only 4600 must go through
      await expect(
        contract
          .connect(contributors[2])
          .contribute(creator.address, 0, { value: targetAmount })
      ).to.changeEtherBalance(contributors[2], -4600);
    });
    it("should revert if the project target is already met", async () => {
      await expect(
        contract
          .connect(contributors[1])
          .contribute(creator.address, 0, { value: 500 })
      ).to.revertedWith("target met");
    });
  });

  describe("Requesting funds", async () => {
    it("should revert if the requested funds are too high", async () => {
      // Requesting funds
      await expect(
        contract.requestFunds(
          0,
          500000,
          contributors[10].address,
          "dance party"
        )
      )
        .to.revertedWithCustomError(contract, "Overspend")
        .withArgs(targetAmount);
    });
    it("should successfully request for 500 wei after target is reached", async () => {
      await contract.requestFunds(
        0,
        500,
        contributors[11].address,
        "server upgrade"
      );
      const project = await getProject();
      expect(project.spendRequests[0].receiver).to.equal(
        contributors[11].address
      );
    });
  });

  describe("Approving spending requests", () => {
    it("should revert if a non-contributor tries to approve", async () => {
      await expect(
        contract.connect(contributors[8]).approve(creator.address, 0, 0)
      ).to.revertedWithCustomError(contract, "NotAContributor");
    });
    it("should revert if a contributor approves twice", async () => {
      await contract.connect(contributors[1]).approve(creator.address, 0, 0);
      // Should revert this time
      await expect(
        contract.connect(contributors[1]).approve(creator.address, 0, 0)
      ).to.revertedWithCustomError(contract, "AlreadyApproved");
    });
  });
});
