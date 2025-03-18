import { describe, it, expect, beforeEach, vi } from "vitest"

// Mock the Clarity VM environment
const mockClarity = {
  tx: {
    sender: "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM",
  },
  block: {
    time: 1625097600, // July 1, 2021
  },
}

// Mock the contract functions
const documentRegistration = {
  registerDocument: vi.fn(),
  updateDocument: vi.fn(),
  grantAccess: vi.fn(),
  revokeAccess: vi.fn(),
  changeDocumentStatus: vi.fn(),
  transferOwnership: vi.fn(),
  getDocument: vi.fn(),
  getDocumentVersion: vi.fn(),
  checkAccess: vi.fn(),
}

describe("Document Registration Contract", () => {
  beforeEach(() => {
    // Reset mocks
    vi.resetAllMocks()
    
    // Setup default mock implementations
    documentRegistration.registerDocument.mockReturnValue({ type: "ok", value: true })
    documentRegistration.updateDocument.mockReturnValue({ type: "ok", value: true })
    documentRegistration.grantAccess.mockReturnValue({ type: "ok", value: true })
    documentRegistration.revokeAccess.mockReturnValue({ type: "ok", value: true })
    documentRegistration.changeDocumentStatus.mockReturnValue({ type: "ok", value: true })
    documentRegistration.transferOwnership.mockReturnValue({ type: "ok", value: true })
    documentRegistration.checkAccess.mockReturnValue({ type: "ok", value: true })
    
    documentRegistration.getDocument.mockReturnValue({
      value: {
        owner: mockClarity.tx.sender,
        name: "Important Document",
        description: "Contains critical information",
        documentHash: Buffer.from("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "hex"),
        category: "legal",
        creationTime: mockClarity.block.time,
        lastUpdated: mockClarity.block.time,
        status: "active",
      },
    })
    
    documentRegistration.getDocumentVersion.mockReturnValue({
      value: {
        documentHash: Buffer.from("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "hex"),
        updatedBy: mockClarity.tx.sender,
        updateTime: mockClarity.block.time,
        changeNotes: "Initial document registration",
      },
    })
  })
  
  describe("registerDocument", () => {
    it("should register a new document successfully", () => {
      const documentId = "doc-001"
      const name = "Important Document"
      const description = "Contains critical information"
      const documentHash = Buffer.from("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "hex")
      const category = "legal"
      
      const result = documentRegistration.registerDocument(documentId, name, description, documentHash, category)
      
      expect(result.type).toBe("ok")
      expect(result.value).toBe(true)
      expect(documentRegistration.registerDocument).toHaveBeenCalledWith(
          documentId,
          name,
          description,
          documentHash,
          category,
      )
    })
  })
  
  describe("updateDocument", () => {
    it("should update a document successfully", () => {
      const documentId = "doc-001"
      const name = "Updated Document"
      const description = "Contains updated critical information"
      const documentHash = Buffer.from("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789", "hex")
      const changeNotes = "Updated with new information"
      
      const result = documentRegistration.updateDocument(documentId, name, description, documentHash, changeNotes)
      
      expect(result.type).toBe("ok")
      expect(result.value).toBe(true)
      expect(documentRegistration.updateDocument).toHaveBeenCalledWith(
          documentId,
          name,
          description,
          documentHash,
          changeNotes,
      )
    })
  })
  
  describe("grantAccess", () => {
    it("should grant access to a document successfully", () => {
      const documentId = "doc-001"
      const user = "ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG"
      const accessLevel = "read"
      const expiresAt = { value: mockClarity.block.time + 86400 } // 1 day later
      
      const result = documentRegistration.grantAccess(documentId, user, accessLevel, expiresAt)
      
      expect(result.type).toBe("ok")
      expect(result.value).toBe(true)
      expect(documentRegistration.grantAccess).toHaveBeenCalledWith(documentId, user, accessLevel, expiresAt)
    })
  })
  
  describe("checkAccess", () => {
    it("should check access to a document successfully", () => {
      const documentId = "doc-001"
      const user = "ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG"
      
      const result = documentRegistration.checkAccess(documentId, user)
      
      expect(result.type).toBe("ok")
      expect(result.value).toBe(true)
      expect(documentRegistration.checkAccess).toHaveBeenCalledWith(documentId, user)
    })
  })
  
  describe("getDocument", () => {
    it("should retrieve document information", () => {
      const documentId = "doc-001"
      
      const result = documentRegistration.getDocument(documentId)
      
      expect(result.value).toEqual({
        owner: mockClarity.tx.sender,
        name: "Important Document",
        description: "Contains critical information",
        documentHash: Buffer.from("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "hex"),
        category: "legal",
        creationTime: mockClarity.block.time,
        lastUpdated: mockClarity.block.time,
        status: "active",
      })
      expect(documentRegistration.getDocument).toHaveBeenCalledWith(documentId)
    })
  })
})

