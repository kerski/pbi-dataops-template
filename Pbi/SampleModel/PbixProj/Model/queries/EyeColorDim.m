let
    Source = MarvelSource,
    #"Removed Other Columns" = Table.SelectColumns(Source,{"EYE"}),
    #"Duplicated Column" = Table.DuplicateColumn(#"Removed Other Columns", "EYE", "EYE - Copy"),
    #"Removed Duplicates" = Table.Distinct(#"Duplicated Column", {"EYE"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Duplicates",{{"EYE", "EyeKey"}}),
    #"Split Column by Delimiter" = Table.SplitColumn(#"Renamed Columns", "EYE - Copy", Splitter.SplitTextByDelimiter(" ", QuoteStyle.Csv), {"EYE - Copy.1", "EYE - Copy.2"}),
    #"Changed Type" = Table.TransformColumnTypes(#"Split Column by Delimiter",{{"EYE - Copy.1", type text}, {"EYE - Copy.2", type text}}),
    #"Removed Columns" = Table.RemoveColumns(#"Changed Type",{"EYE - Copy.2"}),
    #"Sorted Rows" = Table.Sort(#"Removed Columns",{{"EYE - Copy.1", Order.Ascending}}),
    #"Added Index" = Table.AddIndexColumn(#"Sorted Rows", "Index", 0, 1, Int64.Type),
    #"Reordered Columns" = Table.ReorderColumns(#"Added Index",{"Index", "EyeKey", "EYE - Copy.1"}),
    #"Renamed Columns1" = Table.RenameColumns(#"Reordered Columns",{{"Index", "EyeID"}, {"EYE - Copy.1", "Eye Color"}}),
    #"Replaced Value" = Table.ReplaceValue(#"Renamed Columns1","","Not Available",Replacer.ReplaceValue,{"Eye Color"})
in
    #"Replaced Value"