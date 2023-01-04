let
    Source = MarvelSource,
    #"Changed Type" = Table.TransformColumnTypes(Source,{{"page_id", Int64.Type}, {"name", type text}, {"urlslug", type text}, {"ID", type text}, {"ALIGN", type text}, {"EYE", type text}, {"HAIR", type text}, {"SEX", type text}, {"GSM", type text}, {"ALIVE", type text}, {"APPEARANCES", Int64.Type}, {"FIRST APPEARANCE", type text}, {"Year", Int64.Type}}),
    #"Split Column by Delimiter" = Table.SplitColumn(#"Changed Type", "FIRST APPEARANCE", Splitter.SplitTextByDelimiter("-", QuoteStyle.Csv), {"FIRST APPEARANCE.1", "FIRST APPEARANCE.2"}),
    #"Changed Type1" = Table.TransformColumnTypes(#"Split Column by Delimiter",{{"FIRST APPEARANCE.1", type text}, {"FIRST APPEARANCE.2", Int64.Type}}),
    #"Added Custom" = Table.AddColumn(#"Changed Type1", "DateKey", each [FIRST APPEARANCE.1]&"-"&Text.From([Year])),
    #"Replaced Value" = Table.ReplaceValue(#"Added Custom",null,"Jan-0001",Replacer.ReplaceValue,{"DateKey"}),
    #"Removed Columns" = Table.RemoveColumns(#"Replaced Value",{"FIRST APPEARANCE.1", "FIRST APPEARANCE.2", "Year"}),
    #"Merged Queries" = Table.NestedJoin(#"Removed Columns", {"DateKey"}, DateDim, {"DateKey"}, "DateDim", JoinKind.LeftOuter),
    #"Expanded DateDim" = Table.ExpandTableColumn(#"Merged Queries", "DateDim", {"DateID"}, {"DateDim.DateID"}),
    #"Removed Columns1" = Table.RemoveColumns(#"Expanded DateDim",{"DateKey"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Columns1",{{"DateDim.DateID", "DateID"}}),
    #"Removed Columns2" = Table.RemoveColumns(#"Renamed Columns",{"SEX", "GSM", "ALIVE", "urlslug"}),
    #"Merged Queries1" = Table.NestedJoin(#"Removed Columns2", {"EYE"}, EyeColorDim, {"EyeKey"}, "EyeColorDim", JoinKind.LeftOuter),
    #"Expanded EyeColorDim" = Table.ExpandTableColumn(#"Merged Queries1", "EyeColorDim", {"EyeID"}, {"EyeID"}),
    #"Removed Columns3" = Table.RemoveColumns(#"Expanded EyeColorDim",{"HAIR"}),
    #"Merged Queries2" = Table.NestedJoin(#"Removed Columns3", {"ALIGN"}, AlignmentDim, {"AlignmentKey"}, "AlignmentDim", JoinKind.LeftOuter),
    #"Expanded AlignmentDim" = Table.ExpandTableColumn(#"Merged Queries2", "AlignmentDim", {"AlignmentID"}, {"AlignmentID"}),
    #"Removed Columns4" = Table.RemoveColumns(#"Expanded AlignmentDim",{"ID", "ALIGN", "EYE"}),
    #"Renamed Columns1" = Table.RenameColumns(#"Removed Columns4",{{"name", "Name"}, {"APPEARANCES", "Appearances"}, {"page_id", "ID"}})
in
    #"Renamed Columns1"