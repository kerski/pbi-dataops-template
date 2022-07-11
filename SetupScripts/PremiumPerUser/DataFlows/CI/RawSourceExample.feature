 
Feature: RawSourceExample

Background: The Connection to Azure Data Lake Storage Gen2 Exists
    Given we have access to the Azure Subscription named {SUB_NAME}
    And we have access to the Storage Account named {STORAGE_ACCOUNT_NAME}
    And we have the \DataFlows\{WORKSPACE_NAME}\RawSourceExample\model.json file

Scenario: Validate MarvelSource Schema
	Given we have an entity called MarvelSource
	Then it should contain the schema defined as follows:
	| Name          | Type |
	| page_id       | int64        |
	| name          | string        |
    | urlslug       | string        |

Scenario: Validate MarvelSource Data
	Given we have an entity called MarvelSource
	And we have a data file called MarvelSource.csv
	Then there should be 16375 entities returned
	And the unique count of page_id is 16375
	And the max value of Year is 2013
	And the minimum value of Year is 1939
	And the unique count of ALIGN is 3
	And the values of Year matches this regex: "^\d{4}$"
	And the values of ALIVE matches this regex: "^|((Living|Deceased)\sCharacters$)"
	
