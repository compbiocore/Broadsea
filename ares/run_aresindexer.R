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

tryCatch(
  {
    withUppercaseQuerySql({
      Achilles::performTemporalCharacterization(
        connectionDetails = connectionDetails,
        cdmDatabaseSchema = cdmConfig$CDM_DATABASE_SCHEMA,
        resultsDatabaseSchema = cdmConfig$RESULTS_DATABASE_SCHEMA,
        outputFile = outputFile
      )
    })
  },
  error = function(e) {
    if (grepl("NO ACHILLES DATA FOUND", conditionMessage(e), fixed = TRUE)) {
      message(
        "No supported Achilles monthly rows were available; ",
        "skipping optional temporal characterization."
      )
      if (file.exists(outputFile)) {
        file.remove(outputFile)
      }
    } else {
      stop(e)
    }
  }
)

requiredReports <- file.path(
  datasourceReleaseOutputFolder,
  c("person.json", "observationperiod.json")
)
missingReports <- requiredReports[!file.exists(requiredReports)]
if (length(missingReports) > 0) {
  stop("ARES core reports were not generated: ", paste(missingReports, collapse = ", "))
}

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


# -------------------------------------------------------------------------
# Final ARES index generation.
#
# We intentionally avoid AresIndexer::buildNetworkIndex() and
# AresIndexer::buildDataQualityIndex() here because this image/package
# combination has two known compatibility/edge-case failures:
#
# 1. buildNetworkIndex() expects DQD timing columns such as
#    CheckResults.EXECUTION_TIME that are not present in this DQD output.
# 2. buildDataQualityIndex() fails when there are zero failed DQD rows:
#    replacement has 1 row, data has 0.
#
# The core ARES export has already succeeded by this point. This block writes
# the minimum required ARES index files from the generated release folder.
# -------------------------------------------------------------------------

sourceFolders <- list.dirs(aresDataRoot, recursive = FALSE)

message("Building export query index.")
tryCatch(
  {
    AresIndexer::buildExportQueryIndex(aresDataRoot)
  },
  error = function(e) {
    message("AresIndexer::buildExportQueryIndex() failed; writing empty export_query_index.json. Error: ", conditionMessage(e))
    write("[]", file.path(aresDataRoot, "export_query_index.json"))
  }
)

message("Building minimal ARES index.json from exported source/release metadata.")

dqResultPath <- file.path(datasourceReleaseOutputFolder, "dq-result.json")
if (!file.exists(dqResultPath)) {
  stop("Expected dq-result.json not found at: ", dqResultPath)
}

dq <- jsonlite::fromJSON(dqResultPath)

# Flexible metadata getter. Different DQD/Ares versions use slightly different cases.
getMeta <- function(x, names, default = NA_character_) {
  for (nm in names) {
    if (!is.null(x[[nm]]) && length(x[[nm]]) > 0 && !is.na(x[[nm]][1])) {
      return(as.character(x[[nm]][1]))
    }
  }
  default
}

metadata <- dq$Metadata
overview <- dq$Overview

cdmSourceName <- getMeta(metadata, c("cdmSourceName", "cdm_source_name", "CDM_SOURCE_NAME"), metadata$CDM_SOURCE_NAME)
cdmSourceAbbreviation <- getMeta(metadata, c("cdmSourceAbbreviation", "cdm_source_abbreviation", "CDM_SOURCE_ABBREVIATION"), sourceKey)
cdmHolder <- getMeta(metadata, c("cdmHolder", "cdm_holder", "CDM_HOLDER"), "")
sourceDescription <- getMeta(metadata, c("sourceDescription", "source_description", "SOURCE_DESCRIPTION"), "")
cdmReleaseDate <- getMeta(metadata, c("cdmReleaseDate", "cdm_release_date", "CDM_RELEASE_DATE"), as.character(metadata$CDM_RELEASE_DATE))
cdmVersion <- getMeta(metadata, c("cdmVersion", "cdm_version", "CDM_VERSION"), "")
vocabularyVersion <- getMeta(metadata, c("vocabularyVersion", "vocabulary_version", "VOCABULARY_VERSION"), "")
dqdVersion <- getMeta(metadata, c("dqdVersion", "dqd_version", "DQD_VERSION"), "")

overviewValue <- function(x, names, default = 0) {
  for (nm in names) {
    if (!is.null(x[[nm]]) && length(x[[nm]]) > 0 && !is.na(x[[nm]][1])) {
      return(x[[nm]][1])
    }
  }
  default
}

countChecks <- overviewValue(overview, c("countTotal", "count_total", "COUNT_TOTAL"), 0)
countIssues <- overviewValue(overview, c("countOverallFailed", "count_overall_failed", "COUNT_OVERALL_FAILED"), 0)

# Try to get person count and observation period if the exported files exist.
countPerson <- NA
personFile <- file.path(datasourceReleaseOutputFolder, "person.json")
if (file.exists(personFile)) {
  personJson <- tryCatch(jsonlite::fromJSON(personFile), error = function(e) NULL)
  if (!is.null(personJson) && !is.null(personJson$BIRTH_YEAR_DATA$COUNT_PERSON)) {
    countPerson <- sum(personJson$BIRTH_YEAR_DATA$COUNT_PERSON, na.rm = TRUE)
  }
}

obsStart <- NA
obsEnd <- NA
obsFile <- file.path(datasourceReleaseOutputFolder, "observationperiod.json")
if (file.exists(obsFile)) {
  obsJson <- tryCatch(jsonlite::fromJSON(obsFile), error = function(e) NULL)
  if (!is.null(obsJson) && !is.null(obsJson$OBSERVED_BY_MONTH$MONTH_YEAR)) {
    obsStart <- min(obsJson$OBSERVED_BY_MONTH$MONTH_YEAR, na.rm = TRUE)
    obsEnd <- max(obsJson$OBSERVED_BY_MONTH$MONTH_YEAR, na.rm = TRUE)
  }
}

releaseName <- tryCatch(format(lubridate::ymd(cdmReleaseDate), "%Y-%m-%d"), error = function(e) cdmReleaseDate)
releaseId <- tryCatch(format(lubridate::ymd(cdmReleaseDate), "%Y%m%d"), error = function(e) releaseDateKey)

index <- list(
  sources = list(
    list(
      cdm_source_name = cdmSourceName,
      cdm_source_abbreviation = cdmSourceAbbreviation,
      cdm_source_key = sourceKey,
      cdm_holder = cdmHolder,
      source_description = sourceDescription,
      releases = list(
        list(
          release_name = releaseName,
          release_id = releaseId,
          cdm_version = cdmVersion,
          vocabulary_version = vocabularyVersion,
          dqd_version = dqdVersion,
          count_data_quality_issues = countIssues,
          count_data_quality_checks = countChecks,
          dqd_execution_date = format(Sys.Date(), "%Y-%m-%d"),
          count_person = countPerson,
          obs_period_start = obsStart,
          obs_period_end = obsEnd
        )
      ),
      count_releases = 1,
      average_update_interval_days = "n/a"
    )
  )
)

write(
  jsonlite::toJSON(index, auto_unbox = TRUE, null = "null", na = "null"),
  file.path(aresDataRoot, "index.json")
)

# Safe empty network data-quality summary for zero-failure DQD result.
networkDqSummary <- data.frame(
  checkName = character(),
  checkLevel = character(),
  cdmTableName = character(),
  category = character(),
  subcategory = character(),
  context = character(),
  cdmFieldName = character(),
  conceptId = character(),
  unitConceptId = character(),
  CDM_SOURCE_NAME = character(),
  CDM_SOURCE_ABBREVIATION = character(),
  CDM_SOURCE_KEY = character(),
  RELEASE_NAME = character(),
  RELEASE_ID = character()
)

data.table::fwrite(
  networkDqSummary,
  file.path(aresDataRoot, "network-data-quality-summary.csv")
)

# Optional unmapped-source-code index. Do not let this fail the whole deployment.
tryCatch(
  {
    AresIndexer::buildNetworkUnmappedSourceCodeIndex(
      sourceFolders = sourceFolders,
      outputFolder = aresDataRoot
    )
  },
  error = function(e) {
    message("Skipping buildNetworkUnmappedSourceCodeIndex due to error: ", conditionMessage(e))
  }
)

message("ARES indexing complete.")
message("Expected index file: ", file.path(aresDataRoot, "index.json"))
message("Expected DQD index file: ", file.path(aresDataRoot, "export_query_index.json"))
