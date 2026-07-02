source("/postprocessing/init.R")

envVarNames <- list(
  "ARES_RUN_NETWORK"
)

jobConfig <- as.list(Sys.getenv(envVarNames, unset = NA))

aresDataRoot <- Sys.getenv("ARES_DATA_ROOT", unset = "/ares-data")

if (!dir.exists(aresDataRoot)) {
  dir.create(aresDataRoot, recursive = TRUE)
}

message("Ares data root: ", aresDataRoot)
message("CDM schema: ", cdmConfig$CDM_DATABASE_SCHEMA)
message("Results schema: ", cdmConfig$RESULTS_DATABASE_SCHEMA)
message("Vocab schema: ", cdmConfig$VOCAB_DATABASE_SCHEMA)

# Export Achilles results into Ares format first.
Achilles::exportToAres(
  connectionDetails = connectionDetails,
  cdmDatabaseSchema = cdmConfig$CDM_DATABASE_SCHEMA,
  resultsDatabaseSchema = cdmConfig$RESULTS_DATABASE_SCHEMA,
  vocabDatabaseSchema = cdmConfig$VOCAB_DATABASE_SCHEMA,
  outputPath = aresDataRoot,
  reports = c()
)

# Try to get the Ares source-release key.
releaseKey <- AresIndexer::getSourceReleaseKey(
  connectionDetails = connectionDetails,
  cdmDatabaseSchema = cdmConfig$CDM_DATABASE_SCHEMA
)

# Fallback if AresIndexer cannot infer the key.
if (length(releaseKey) == 0 || is.na(releaseKey) || !nzchar(releaseKey)) {
  message("AresIndexer::getSourceReleaseKey() returned empty. Searching Ares data root for generated release folder.")

  sourceFolders <- list.dirs(aresDataRoot, recursive = FALSE, full.names = FALSE)
  sourceFolders <- sourceFolders[!sourceFolders %in% c("", ".", "..")]

  if (length(sourceFolders) > 0) {
    releaseKey <- sourceFolders[[1]]
  } else {
    releaseKey <- paste0(
      gsub("[^A-Za-z0-9_\\-]", "_", cdmConfig$CDM_DATABASE_SCHEMA),
      "_",
      format(Sys.Date(), "%Y%m%d")
    )
  }
}

message("Using Ares releaseKey: ", releaseKey)

datasourceReleaseOutputFolder <- file.path(aresDataRoot, releaseKey)

if (!dir.exists(datasourceReleaseOutputFolder)) {
  dir.create(path = datasourceReleaseOutputFolder, recursive = TRUE)
}

# Copy DQD results JSON into the Ares release folder.
dqdFilePath <- file.path(
  "/postprocessing",
  "dqd",
  "data",
  cdmConfig$CDM_DATABASE_SCHEMA,
  "dq-result.json"
)

if (!file.exists(dqdFilePath)) {
  stop("DQD result file not found: ", dqdFilePath)
}

file.copy(
  from = dqdFilePath,
  to = file.path(datasourceReleaseOutputFolder, "dq-result.json"),
  overwrite = TRUE
)

# Temporal characterization.
outputFile <- file.path(datasourceReleaseOutputFolder, "temporal-characterization.csv")

Achilles::performTemporalCharacterization(
  connectionDetails = connectionDetails,
  cdmDatabaseSchema = cdmConfig$CDM_DATABASE_SCHEMA,
  resultsDatabaseSchema = cdmConfig$RESULTS_DATABASE_SCHEMA,
  outputFile = outputFile
)

# Augment concept files.
AresIndexer::augmentConceptFiles(
  releaseFolder = datasourceReleaseOutputFolder
)

# Build indexes.
sourceFolders <- list.dirs(aresDataRoot, recursive = FALSE)

AresIndexer::buildNetworkIndex(
  sourceFolders = sourceFolders,
  outputFolder = aresDataRoot
)

AresIndexer::buildDataQualityIndex(
  sourceFolders = sourceFolders,
  outputFolder = aresDataRoot
)

AresIndexer::buildNetworkUnmappedSourceCodeIndex(
  sourceFolders = sourceFolders,
  outputFolder = aresDataRoot
)