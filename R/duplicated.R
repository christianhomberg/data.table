
warning_oldUniqueByKey = "The deprecated option 'datatable.old.unique.by.key' is being used. Please stop using it and pass 'by=key(DT)' instead for clarity. For more information please search the NEWS file for this option."

duplicated.data.table <- function(x, incomparables=FALSE, fromLast=FALSE, by=seq_along(x), ...) {
  if (!cedta()) return(NextMethod("duplicated"))
  if (!identical(incomparables, FALSE)) {
    .NotYetUsed("incomparables != FALSE")
  }
  if (missing(by) && isTRUE(getOption("datatable.old.unique.by.key"))) {  #1284
    by = key(x)
    warning(warning_oldUniqueByKey)
  }
  if (nrow(x) == 0L || ncol(x) == 0L) return(logical(0)) # fix for bug #5582
  if (is.na(fromLast) || !is.logical(fromLast)) stop("'fromLast' must be TRUE or FALSE")
  query <- .duplicated.helper(x, by)
  # fix for bug #5405 - unique on null data table returns error (because of 'forderv')
  # however, in this case we can bypass having to go to forderv at all.
  if (!length(query$by)) return(logical(0))

  if (query$use.keyprefix) {
    f = uniqlist(shallow(x, query$by))
    if (fromLast) f = cumsum(uniqlengths(f, nrow(x)))
  } else {
    o = forderv(x, by=query$by, sort=FALSE, retGrp=TRUE)
    if (attr(o, 'maxgrpn') == 1L) return(rep.int(FALSE, nrow(x)))
    f = attr(o,"starts")
    if (fromLast) f = cumsum(uniqlengths(f, nrow(x)))
    if (length(o)) f = o[f]
  }
  res <- rep.int(TRUE, nrow(x))
  res[f] = FALSE
  res
}

unique.data.table <- function(x, incomparables=FALSE, fromLast=FALSE, by=seq_along(x), ...) {
  if (!cedta()) return(NextMethod("unique"))
  if (!identical(incomparables, FALSE)) {
    .NotYetUsed("incomparables != FALSE")
  }
  if (nrow(x) <= 1L) return(x)
  if (missing(by) && isTRUE(getOption("datatable.old.unique.by.key"))) {
    by = key(x)
    warning(warning_oldUniqueByKey)
  } else if (is.null(by)) by=seq_along(x)
  o = forderv(x, by=by, sort=FALSE, retGrp=TRUE)
  # if by=key(x), forderv tests for orderedness within it quickly and will short-circuit
  # there isn't any need in unique() to call uniqlist like duplicated does; uniqlist retuns a new nrow(x) vector anyway and isn't
  # as efficient as forderv returning empty o when input is already ordered
  if (attr(o, 'maxgrpn') == 1L) return(x)  # avoid copy. Oftentimes, user just wants to check DT is unique with perhaps nrow(unique(DT))==nrow(DT)
  f = attr(o,"starts")
  if (fromLast) f = cumsum(uniqlengths(f, nrow(x)))
  if (length(o)) f = o[f]
  if (length(o <- forderv(f))) f = f[o]  # don't sort the uniques too
  .Call(CsubsetDT, x, f, seq_len(ncol(x)))
  # TO DO: allow by=NULL to mean all, for further speed gain.
  #        See news for v1.9.3 for link to benchmark use-case on datatable-help.
}

# Test for #2013 unique() memory efficiency improvement in v1.10.5
# set.seed(1)
# Create unique 7.6GB DT on 16GB laptop
# DT = data.table(
#  A = sample(1e8, 2e8, TRUE),
#  B = sample(1e8, 2e8, TRUE),
#  C = 1:2e8,
#  D = 1:2e8,
#  E = 1:2e8,
#  F = 1:2e8,
#  G = 1:2e8,
#  H = 1:2e8,
#  I = 1:2e8,
#  J = 1:2e8
# )
# print(dim(unique(DT)))  # works now, failed with oom in 1.10.4-3


## Specify the column names to be used in the uniqueness query, and if this
## query can take advantage of the keys of `x` (if present).
## returns a list
##
## This was dropped into a helper because initial implementation of
## unique.data.table and duplicated.data.table both needed this. However,
## unique.data.table has been refactored to simply call duplicated.data.table
## making the refactor unnecessary, but let's leave it here just in case
.duplicated.helper <- function(x, by) {
  use.sub.cols <- !is.null(by) # && !isTRUE(by) # Fixing bug #5424

  if (use.sub.cols) {
    ## Did the user specify (integer) indexes for the columns?
    if (is.numeric(by)) {
      if (any(as.integer(by) != by) || any(by<1) || any(by>ncol(x))) {
        stop("Integer values between 1 and ncol are required for 'by' when ",
             "column indices. It's often better to use column names.")
      }
      by <- names(x)[by]
    }
    if (!is.character(by)) {
      stop("Only NULL, column indices or column names are allowed in by")
    }
    bad.cols <- setdiff(by, names(x))
    if (length(bad.cols)) {
      stop("by specifies column names that do not exist. First 5: ",paste(head(bad.cols,5),collapse=","))
    }

    use.keyprefix = haskey(x) &&
      length(by) <= length(key(x)) &&
      all(head(key(x), length(by)) == by)
  } else {
    ## by is not was explicitly set to
    use.keyprefix = FALSE
    by = names(x)
  }

  list(use.keyprefix=use.keyprefix, by=by)
}

# FR #5172 anyDuplicated.data.table
# Note that base's anyDuplicated is faster than any(duplicated(.)) (for vectors) - for data.frames it still pastes before calling duplicated
# In that sense, this anyDuplicated is *not* the same as base's - meaning it's not a different implementation
# This is just a wrapper. That being said, it should be incredibly fast on data.tables (due to data.table's fast forder)
anyDuplicated.data.table <- function(x, incomparables=FALSE, fromLast=FALSE, by=seq_along(x), ...) {
  if (!cedta()) return(NextMethod("anyDuplicated"))
  if (missing(by) && isTRUE(getOption("datatable.old.unique.by.key"))) {
    by = key(x)
    warning(warning_oldUniqueByKey)
  }
  dups <- duplicated(x, incomparables, fromLast, by, ...)
  if (fromLast) idx = tail(which(dups), 1L) else idx = head(which(dups), 1L)
  if (!length(idx)) idx=0L
  idx
}

# simple straightforward helper function to get the number
# of groups in a vector or data.table. Here by data.table,
# we really mean `.SD` - used in a grouping operation
# TODO: optimise uniqueN further with GForce.
uniqueN <- function(x, by = if (is.list(x)) seq_along(x) else NULL, na.rm=FALSE) { # na.rm, #1455
  if (missing(by) && is.data.table(x) && isTRUE(getOption("datatable.old.unique.by.key"))) {
    by = key(x)
    warning(warning_oldUniqueByKey)
  }
  if (is.null(x)) return(0L)
  if (!is.atomic(x) && !is.data.frame(x))
    stop("x must be an atomic vector or data.frames/data.tables")
  if (is.atomic(x)) x = as_list(x)
  if (is.null(by)) by = seq_along(x)
  o = forderv(x, by=by, retGrp=TRUE, na.last=if (!na.rm) FALSE else NA)
  starts = attr(o, 'starts')
  if (!na.rm) {
    length(starts)
  } else {
    # TODO: internal efficient sum
    # fix for #1771, account for already sorted input
    sum( (if (length(o)) o[starts] else starts) != 0L)
  }
}

