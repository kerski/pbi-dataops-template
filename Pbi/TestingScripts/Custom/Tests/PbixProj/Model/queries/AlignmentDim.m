let
    Source = MarvelSource,
    #"Removed Other Columns" = Table.SelectColumns(Source,{"ALIGN"}),
    #"Removed Duplicates" = Table.Distinct(#"Removed Other Columns"),
    #"Duplicated Column" = Table.DuplicateColumn(#"Removed Duplicates", "ALIGN", "ALIGN - Copy"),
    #"Renamed Columns" = Table.RenameColumns(#"Duplicated Column",{{"ALIGN - Copy", "AlignmentKey"}}),
    #"Split Column by Delimiter" = Table.SplitColumn(#"Renamed Columns", "ALIGN", Splitter.SplitTextByDelimiter(" ", QuoteStyle.Csv), {"ALIGN.1", "ALIGN.2"}),
    #"Changed Type" = Table.TransformColumnTypes(#"Split Column by Delimiter",{{"ALIGN.1", type text}, {"ALIGN.2", type text}}),
    #"Renamed Columns1" = Table.RenameColumns(#"Changed Type",{{"ALIGN.1", "Alignment"}}),
    #"Sorted Rows" = Table.Sort(#"Renamed Columns1",{{"Alignment", Order.Ascending}}),
    #"Replaced Value" = Table.ReplaceValue(#"Sorted Rows","","Not Available",Replacer.ReplaceValue,{"Alignment"}),
    #"Added Index" = Table.AddIndexColumn(#"Replaced Value", "Index", 0, 1, Int64.Type),
    #"Renamed Columns2" = Table.RenameColumns(#"Added Index",{{"Index", "AlignmentID"}}),
    #"Reordered Columns" = Table.ReorderColumns(#"Renamed Columns2",{"AlignmentID", "Alignment", "ALIGN.2", "AlignmentKey"}),
    #"Removed Columns" = Table.RemoveColumns(#"Reordered Columns",{"ALIGN.2"})
in
    #"Removed Columns"