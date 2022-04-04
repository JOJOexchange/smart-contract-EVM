import { revert, snapshot } from "./timemachine";

let snapshotID:string;

beforeEach(async () => {
    snapshotID = await snapshot();
});

afterEach(async () => {
    if (snapshotID) {
        await revert(snapshotID);
    }
    snapshotID = "";
});