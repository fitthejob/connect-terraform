import {
  CustomerProfilesClient,
  SearchProfilesCommand,
} from "@aws-sdk/client-customer-profiles";

const client = new CustomerProfilesClient({ region: process.env.AWS_REGION });

export const handler = async (event: any) => {
  const phoneNumber = event.Details.ContactData.CustomerEndpoint.Address;
  const domainName = process.env.CUSTOMER_PROFILES_DOMAIN;

  try {
    const command = new SearchProfilesCommand({
      DomainName: domainName,
      KeyName: "_phone",
      Values: [phoneNumber],
    });

    const response = await client.send(command);
    const profile = response.Items?.[0];

    if (!profile) {
      return {
        customerTier: "STANDARD",
        eligibilityFound: "false",
      };
    }

    return {
      customerTier: profile.Attributes?.["customerTier"] ?? "STANDARD",
      eligibilityFound: "true",
    };
  } catch (error) {
    console.error("Customer Profiles lookup failed:", error);
    return {
      customerTier: "STANDARD",
      eligibilityFound: "false",
    };
  }
};
