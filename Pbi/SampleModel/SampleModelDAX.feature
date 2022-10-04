
Feature: SampleModel DAX

Background: The Connection to the Power BI Report exists
    Given that we have access to the Power BI Report named "SampleModel"

Scenario Outline: Dataset passes tests
    Given we have the <TestFile> file
    Then the <TestFile> file should pass its tests

    Scenarios: DAX test files
    | TestFile |
    | CalculatedColumnsTests |    
    | MeasureTests |    
	
