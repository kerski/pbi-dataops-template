Feature: SampleModel Schema

Background: The Connection to the Power BI Report exists
    Given that we have access to the Power BI Report named "SampleModel"
    And we have the following properties
    """
    {
        "SchemaScriptPath": ".\\Pbi\\TestingScripts\\Custom\\GetSchema.cs",
        "TabularEditorPath": ".\\Pbi\\TestingScripts\\TabularEditor\\TabularEditor.2.17.1\\TabularEditor.exe"
    }
    """
    And we have the schema for "SampleModel"

Scenario: Validate AlignmentDim Schema
	Given we have a table called "AlignmentDim"
    Then it should contain the schema defined as follows:
	| Name          | Type  | Format |
	| Alignment     | string|        |
	| AlignmentID   | int64 |    0   |
    | AlignmentKey  | string|    0    |

Scenario: Validate AlignmentDim Data
	Given we have a table called "AlignmentDim"
	Then the values of "AlignmentID" matches this regex: "^\d$"
 	And the values of "Alignment" matches this regex: "^Bad|Good|Neutral|Not Available$"   
