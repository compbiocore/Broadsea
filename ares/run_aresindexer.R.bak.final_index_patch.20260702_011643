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

getCdmSourceMetadata <- function() {
  conn <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

  sql <- SqlRender::render(
    sql = "
      select
        cdm_source_name,
        cdm_source_abbreviation,
        cdm_holder,
        source_description,
        source_documentation_reference,
        cdm_etl_reference,
        source_release_date,
        cdm_release_date,
        cdm_version,
        cdm_version_concept_id,
        vocabulary_version
      from @cdmDatabaseSchema.cdm_source;
    ",
    cdmDatabaseSchema = cdmConfig$CDM_DATABASE_SCHEMA
  )

  sql <- SqlRender::translate(
    sql = sql,
    targetDialect = connectionDetails$dbms
  )

  metadata <- DatabaseConnector::querySql(conn, sql)
  names(metadata) <- toupper(names(metadata))

  if (nrow(metadata) < 1) {
    stop("cdm_source has no rows. ARES cannot build output folder.")
  }

  if (!"CDM_SOURCE_ABBREVIATION" %in% names(metadata)) {
    stop("CDM_SOURCE_ABBREVIATION not found in cdm_source metadata.")
  }

  if (!"CDM_RELEASE_DATE" %in% names(metadata)) {
    stop("CDM_RELEASE_DATE not found in cdm_source metadata.")
  }

  if (is.na(metadata$CDM_SOURCE_ABBREVIATION[1]) ||
      !nzchar(metadata$CDM_SOURCE_ABBREVIATION[1])) {
    stop("CDM_SOURCE_ABBREVIATION is missing or empty.")
  }

  if (is.na(metadata$CDM_RELEASE_DATE[1])) {
    stop("CDM_RELEASE_DATE is missing or invalid.")
  }

  metadata
}

metadata <- getCdmSourceMetadata()

sourceKey <- gsub(
  pattern = "[^A-Za-z0-9_\\-]",
  replacement = "_",
  x = metadata$CDM_SOURCE_ABBREVIATION[1]
)

releaseDateKey <- format(
  lubridate::ymd(metadata$CDM_RELEASE_DATE[1]),
  "%Y%m%d"
)

releaseKey <- file.path(sourceKey, releaseDateKey)
datasourceReleaseOutputFolder <- file.path(aresDataRoot, releaseKey)

message("ARES sourceKey: ", sourceKey)
message("ARES releaseDateKey: ", releaseDateKey)
message("ARES releaseKey: ", releaseKey)
message("ARES datasourceReleaseOutputFolder: ", datasourceReleaseOutputFolder)

if (is.na(sourceKey) || !nzchar(sourceKey)) {
  stop("Invalid sourceKey.")
}

if (is.na(releaseDateKey) || !nzchar(releaseDateKey)) {
  stop("Invalid releaseDateKey.")
}

dir.create(datasourceReleaseOutputFolder, recursive = TRUE, showWarnings = FALSE)

withUppercaseQuerySql <- function(expr) {
  ns <- asNamespace("DatabaseConnector")
  originalQuerySql <- get("querySql", envir = ns)

  patchedQuerySql <- function(...) {
    result <- originalQuerySql(...)
    if (is.data.frame(result)) {
      names(result) <- toupper(names(result))
    }
    result
  }

  bindingWasLocked <- bindingIsLocked("querySql", ns)

  if (bindingWasLocked) {
    unlockBinding("querySql", ns)
  }

  assign("querySql", patchedQuerySql, envir = ns)

  if (bindingWasLocked) {
    lockBinding("querySql", ns)
  }

  on.exit({
    if (bindingIsLocked("querySql", ns)) {
      unlockBinding("querySql", ns)
    }

    assign("querySql", originalQuerySql, envir = ns)

    if (bindingWasLocked) {
      lockBinding("querySql", ns)
    }
  }, add = TRUE)

  force(expr)
}

withUppercaseQuerySql({
  Achilles::exportToAres(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cdmConfig$CDM_DATABASE_SCHEMA,
    resultsDatabaseSchema = cdmConfig$RESULTS_DATABASE_SCHEMA,
    vocabDatabaseSchema = cdmConfig$VOCAB_DATABASE_SCHEMA,
    outputPath = aresDataRoot,
    reports = c()
  )
})

if (!dir.exists(datasourceReleaseOutputFolder)) {
  stop("Expected ARES release folder was not created: ", datasourceReleaseOutputFolder)
}

message("Using Ares releaseKey: ", releaseKey)

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

outputFile <- file.path(datasourceReleaseOutputFolder, "temporal-characterization.csv")

withUppercaseQuerySql({
  Achilles::performTemporalCharacterization(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cdmConfig$CDM_DATABASE_SCHEMA,
    resultsDatabaseSchema = cdmConfig$RESULTS_DATABASE_SCHEMA,
    outputFile = outputFile
  )
})

AresIndexer::augmentConceptFiles(
  releaseFolder = datasourceReleaseOutputFolder
)


# -------------------------------------------------------------------------
# Patch Achilles::getAnalysisDetails for AresIndexer compatibility.
# This Achilles version returns lowercase columns such as analysis_id/category,
# while AresIndexer expects ANALYSIS_ID/CATEGORY.
# -------------------------------------------------------------------------

patchAchillesGetAnalysisDetails <- function() {
  ns <- asNamespace("Achilles")
  original <- get("getAnalysisDetails", envir = ns)

  patched <- function(...) {
    result <- original(...)

    # Convert analysis_id/category/etc. to ANALYSIS_ID/CATEGORY/etc.
    names(result) <- toupper(names(result))

    if (!"ANALYSIS_ID" %in% names(result)) {
      stop(
        "Patched Achilles::getAnalysisDetails() does not contain ANALYSIS_ID. Columns were: ",
        paste(names(result), collapse = ", ")
      )
    }

    if (!"CATEGORY" %in% names(result)) {
      stop(
        "Patched Achilles::getAnalysisDetails() does not contain CATEGORY. Columns were: ",
        paste(names(result), collapse = ", ")
      )
    }

    result
  }

  wasLocked <- bindingIsLocked("getAnalysisDetails", ns)

  if (wasLocked) {
    unlockBinding("getAnalysisDetails", ns)
  }

  assign("getAnalysisDetails", patched, envir = ns)

  if (wasLocked) {
    lockBinding("getAnalysisDetails", ns)
  }

  message("Patched Achilles::getAnalysisDetails() for AresIndexer compatibility.")
}

patchAchillesGetAnalysisDetails()

sourceFolders <- list.dirs(aresDataRoot, recursive = FALSE)

message("Skipping AresIndexer::buildNetworkIndex() because this AresIndexer/DQD package combination expects DQD timing columns that are not present, e.g. CheckResults.EXECUTION_TIME.")

# AresIndexer::buildNetworkIndex(
#   sourceFolders = sourceFolders,
#   outputFolder = aresDataRoot
# )

AresIndexer::buildDataQualityIndex(
  sourceFolders = sourceFolders,
  outputFolder = aresDataRoot
)

AresIndexer::buildNetworkUnmappedSourceCodeIndex(
  sourceFolders = sourceFolders,
  outputFolder = aresDataRoot
)

message("ARES indexing complete.")
message("Expected index file: ", file.path(aresDataRoot, "index.json"))
message("Expected DQD index file: ", file.path(aresDataRoot, "export_query_index.json"))
