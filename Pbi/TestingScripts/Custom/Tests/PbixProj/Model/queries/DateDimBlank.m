let
    Source = Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText("i45WMlDSUfJKzNM1MDAwBDIN9Q31wczYWAA=", BinaryEncoding.Base64), Compression.Deflate)), let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [DateID = _t, DateKey = _t, Date = _t]),
    #"Changed Type1" = Table.TransformColumnTypes(Source,{{"Date", type date}}),
    #"Changed Type" = Table.TransformColumnTypes(#"Changed Type1",{{"DateID", Int64.Type}, {"DateKey", type text}, {"Date", type date}})
in
    #"Changed Type"