let
    Source = Csv.Document(Web.Contents(WebURL),[Delimiter=",", Columns=13, Encoding=65001, QuoteStyle=QuoteStyle.None]),
    #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{{"page_id", Int64.Type}, {"name", type text}, {"urlslug", type text}, {"ID", type text}, {"ALIGN", type text}, {"EYE", type text}, {"HAIR", type text}, {"SEX", type text}, {"GSM", type text}, {"ALIVE", type text}, {"APPEARANCES", Int64.Type}, {"FIRST APPEARANCE", type text}, {"Year", Int64.Type}})
in
    #"Changed Type"