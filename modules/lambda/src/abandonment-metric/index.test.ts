import { describe, it, expect, vi, beforeEach } from "vitest";

const mockSearchContacts = vi.fn();
const mockDescribeContact = vi.fn();
const mockFilterLogEvents = vi.fn();
const mockGetItem = vi.fn();
const mockPutItem = vi.fn();
const mockPutMetricData = vi.fn();

vi.mock("@aws-sdk/client-connect", () => ({
  ConnectClient: vi.fn(() => ({
    send: vi.fn((cmd) => {
      if (cmd.constructor.name === "SearchContactsCommand") return mockSearchContacts();
      if (cmd.constructor.name === "DescribeContactCommand") return mockDescribeContact();
      return Promise.resolve({});
    }),
  })),
  SearchContactsCommand: vi.fn((input) => ({ constructor: { name: "SearchContactsCommand" }, input })),
  DescribeContactCommand: vi.fn((input) => ({ constructor: { name: "DescribeContactCommand" }, input })),
}));

vi.mock("@aws-sdk/client-cloudwatch-logs", () => ({
  CloudWatchLogsClient: vi.fn(() => ({
    send: vi.fn(() => mockFilterLogEvents()),
  })),
  FilterLogEventsCommand: vi.fn((input) => ({ input })),
}));

vi.mock("@aws-sdk/client-cloudwatch", () => ({
  CloudWatchClient: vi.fn(() => ({
    send: vi.fn(() => mockPutMetricData()),
  })),
  PutMetricDataCommand: vi.fn((input) => ({ input })),
}));

vi.mock("@aws-sdk/lib-dynamodb", () => ({
  DynamoDBDocumentClient: { from: vi.fn(() => ({
    send: vi.fn((cmd) => {
      if (cmd.constructor.name === "GetCommand") return mockGetItem();
      if (cmd.constructor.name === "PutCommand") return mockPutItem();
      return Promise.resolve({});
    }),
  })) },
  GetCommand: vi.fn((input) => ({ constructor: { name: "GetCommand" }, input })),
  PutCommand: vi.fn((input) => ({ constructor: { name: "PutCommand" }, input })),
}));

vi.mock("@aws-sdk/client-dynamodb", () => ({
  DynamoDBClient: vi.fn(() => ({})),
}));

beforeEach(() => {
  vi.clearAllMocks();
  process.env.INSTANCE_ID = "test-instance-id";
  process.env.LOG_GROUP_NAME = "/aws/connect/test-instance";
  process.env.DEDUP_TABLE_NAME = "abandonment-metric-dedup-test";
  process.env.METRIC_NAMESPACE = "ContactCenter/SelfService";
  process.env.STAGE = "test";
  process.env.LOOKBACK_MINUTES = "6";
});

describe("handler", () => {
  it("emits a metric for a new, matched, abandoned contact", async () => {
    mockSearchContacts.mockResolvedValue({
      Contacts: [{ Id: "contact-1" }],
    });
    mockDescribeContact.mockResolvedValue({
      Contact: { DisconnectReason: "CUSTOMER_DISCONNECT", DisconnectTimestamp: "2026-08-14T16:57:15.410000-04:00" },
    });
    mockGetItem.mockResolvedValue({ Item: undefined });
    mockFilterLogEvents.mockResolvedValue({
      events: [
        { message: JSON.stringify({ ContactFlowName: "Module-SmsVerification-dev", ContactFlowModuleType: "GetUserInput", Identifier: "CollectCode", Timestamp: "2026-08-14T16:57:10.009Z" }) },
      ],
    });
    mockPutMetricData.mockResolvedValue({});
    mockPutItem.mockResolvedValue({});

    const { handler } = await import("./index");
    await handler();

    expect(mockPutMetricData).toHaveBeenCalledTimes(1);
    expect(mockPutItem).toHaveBeenCalledTimes(1);
  });

  it("skips a contact already present in the dedup table", async () => {
    mockSearchContacts.mockResolvedValue({ Contacts: [{ Id: "contact-1" }] });
    mockDescribeContact.mockResolvedValue({
      Contact: { DisconnectReason: "CUSTOMER_DISCONNECT", DisconnectTimestamp: "2026-08-14T16:57:15.410000-04:00" },
    });
    mockGetItem.mockResolvedValue({ Item: { contactId: "contact-1" } });

    const { handler } = await import("./index");
    await handler();

    expect(mockFilterLogEvents).not.toHaveBeenCalled();
    expect(mockPutMetricData).not.toHaveBeenCalled();
  });

  it("does not emit a metric when the last unpaired block is not in the registry", async () => {
    mockSearchContacts.mockResolvedValue({ Contacts: [{ Id: "contact-1" }] });
    mockDescribeContact.mockResolvedValue({
      Contact: { DisconnectReason: "CUSTOMER_DISCONNECT", DisconnectTimestamp: "2026-08-14T16:57:15.410000-04:00" },
    });
    mockGetItem.mockResolvedValue({ Item: undefined });
    mockFilterLogEvents.mockResolvedValue({
      events: [
        { message: JSON.stringify({ ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "InvokeExternalResource", Identifier: "PublishInitiated", Timestamp: "2026-08-14T16:57:10.009Z" }) },
      ],
    });
    mockPutItem.mockResolvedValue({});

    const { handler } = await import("./index");
    await handler();

    expect(mockPutMetricData).not.toHaveBeenCalled();
    // Still recorded as processed, so an out-of-registry abandonment isn't
    // re-checked on every future overlapping poll.
    expect(mockPutItem).toHaveBeenCalledTimes(1);
  });
});
