// Construct all columns and measures:
var objects = Model.AllMeasures.Cast<ITabularNamedObject>()
      .Concat(Model.AllColumns);

// Get their properties in TSV format (tabulator-separated):
var tsv = ExportProperties(objects,"Name,ObjectType,Parent,Description,FormatString,DataType,Expression");

// ...or save the TSV to a file:
SaveFile("model.tsv", tsv);