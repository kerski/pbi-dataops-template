// Construct all columns and measures:
var objects = Model.AllMeasures.Cast<ITabularNamedObject>()
      .Concat(Model.AllColumns);

// Get their properties in TSV format (tabulator-separated):
var tsv = ExportProperties(objects,"Name,ObjectType,Parent,Description,FormatString,DataType,Expression");

// (Optional) Output to screen (can then be copy-pasted into Excel):
//tsv.Output();

// ...or save the TSV to a file:
SaveFile("documentation.tsv", tsv);