import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.5.4/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
    name: "Collateral Utility: Entity Registration",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const entityId = "test-entity-001";
        const entityName = "Test Financial Institution";

        const block = chain.mineBlock([
            Tx.contractCall('collateral_utility', 'register-entity', [
                types.ascii(entityId),
                types.ascii(entityName)
            ], deployer.address)
        ]);

        // Assert registration success
        block.receipts[0].result.expectOk().expectBool(true);

        // Verify entity information
        const entityInfo = chain.callReadOnlyFn('collateral_utility', 'get-entity-info', [
            types.ascii(entityId)
        ], deployer.address);

        entityInfo.result.expectSome();
        const entityData = entityInfo.result.expectSome();
        assertEquals(entityData.data.name, entityName);
        assertEquals(entityData.data.owner, deployer.address);
    }
});

Clarinet.test({
    name: "Collateral Utility: Duplicate Entity Registration",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const entityId = "test-entity-002";
        const entityName = "Duplicate Financial Institution";

        // First registration should succeed
        const firstBlock = chain.mineBlock([
            Tx.contractCall('collateral_utility', 'register-entity', [
                types.ascii(entityId),
                types.ascii(entityName)
            ], deployer.address)
        ]);

        firstBlock.receipts[0].result.expectOk().expectBool(true);

        // Second registration with same ID should fail
        const secondBlock = chain.mineBlock([
            Tx.contractCall('collateral_utility', 'register-entity', [
                types.ascii(entityId),
                types.ascii(entityName)
            ], deployer.address)
        ]);

        secondBlock.receipts[0].result.expectErr().expectUint(201); // ERR-COLLATERAL-ALREADY-EXISTS
    }
});

Clarinet.test({
    name: "Collateral Utility: Document Addition",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const entityId = "test-entity-003";
        const documentId = "test-doc-001";
        const documentName = "Test Property Deed";
        const documentDescription = u"Commercial real estate collateral document";
        const documentHash = new Uint8Array(32).fill(1);
        const documentType = "real-estate";

        // First, register the entity
        chain.mineBlock([
            Tx.contractCall('collateral_utility', 'register-entity', [
                types.ascii(entityId),
                types.ascii("Test Financial Institution")
            ], deployer.address)
        ]);

        // Add document
        const block = chain.mineBlock([
            Tx.contractCall('collateral_utility', 'add-document', [
                types.ascii(entityId),
                types.ascii(documentId),
                types.ascii(documentName),
                types.utf8(documentDescription),
                types.buff(documentHash),
                types.ascii(documentType)
            ], deployer.address)
        ]);

        // Assert document addition success
        block.receipts[0].result.expectOk().expectBool(true);

        // Verify document information
        const documentInfo = chain.callReadOnlyFn('collateral_utility', 'get-document-info', [
            types.ascii(entityId),
            types.ascii(documentId)
        ], deployer.address);

        documentInfo.result.expectSome();
        const docData = documentInfo.result.expectSome();
        assertEquals(docData.data.name, documentName);
        assertEquals(docData.data.document_type, documentType);
    }
});

// Add more test cases covering permissions, document updates, access control, etc.