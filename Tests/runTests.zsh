#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# DDM OS Reminder pre-release test suite
#
#   sudo zsh Tests/runTests.zsh [--unit | --integration] [--skip-dialogs] [--filter <text>]
#                               [--keep] [--release <x.y.z> | --prerelease <x.y.zbN>] [--help]
#
# Tests the scripts in the checkout this file lives in (not the copy deployed on the Mac).
# Unit tier: hermetic; writes only under /var/tmp/dor-tests.XXXXXX.
# Integration tier: deploys under the throwaway RDNN com.example.dortest in Script mode only.
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export TZ="America/New_York"

testsRoot="${0:A:h}"
repoRoot="${0:A:h:h}"
rdPath="${repoRoot}/reminderDialog.zsh"
ldmPath="${repoRoot}/launchDaemonManagement.zsh"
asmPath="${repoRoot}/assemble.zsh"
changelogPath="${repoRoot}/CHANGELOG.md"
testRdnn="com.example.dortest"
productionRdnn="org.churchofjesuschrist"
productionDaemonLabel="${productionRdnn}.dor"
repositoryURL="https://github.com/dan-snelson/DDM-OS-Reminder.git"

runTimestamp="$( date '+%Y-%m-%d-%H%M%S' )"
resultsLog="/var/tmp/dor-tests-${runTimestamp}.log"
workDir=""
stubDir=""
extractDir=""

integrationRequested="NO"
skipDialogs="NO"
keepWork="NO"
releaseVersion=""
releaseKind=""
testFilter=""
runArguments="${*}"
originalArguments="${runArguments:-(none)}"

gitCheckout="NO"
gitBinary=""
gitBranch=""
gitCommit=""
repoStatusBefore=""
productionDaemonLoaded="NO"
integrationStarted="NO"
consoleDependentScenarios="YES"

passCount=0
failCount=0
skipCount=0
filteredCount=0
unitFailCount=0

source "${testsRoot}/lib/testHelpers.zsh" || { echo "Unable to load ${testsRoot}/lib/testHelpers.zsh"; exit 69; }



####################################################################################################
#
# Functions
#
####################################################################################################

function printUsage() {
    cat <<'ENDOFUSAGE'
Usage:
  sudo zsh Tests/runTests.zsh [--unit | --integration] [--skip-dialogs] [--filter <text>]
                              [--keep] [--release <x.y.z> | --prerelease <x.y.zbN>] [--help]

Options:
  --unit             Run the hermetic unit tier only (default)
  --integration      Run the unit tier, then the integration tier (deploys com.example.dortest)
  --skip-dialogs     Leave out integration scenarios that show swiftDialog windows
  --filter <text>    Run only tests whose "[group] description" contains <text>
  --keep             Keep the work directory and the com.example.dortest deployment after the run
  --release <x.y.z>  Require every scriptVersion and the top CHANGELOG heading to equal <x.y.z>
  --prerelease <x.y.zbN>
                     Same check for a beta such as 5.4.0b1; the CHANGELOG heading may add
                     a parenthetical, such as (Unreleased) or a date
  --help, -h         Show this help

Results are written to /var/tmp/dor-tests-<YYYY-MM-DD-HHMMSS>.log (path printed last).
See Tests/README.md for tiers, safety notes, and the pre-release workflow.
ENDOFUSAGE
}

function finishRun() {
    local exitStatus="${?}"

    if [[ "${integrationStarted}" == "YES" && "${keepWork}" != "YES" ]]; then
        copyTestRdnnLog
        teardownTestRdnn >/dev/null 2>&1
    elif [[ "${integrationStarted}" == "YES" ]]; then
        copyTestRdnnLog
    fi

    if [[ -n "${workDir}" && "${workDir}" == /var/tmp/dor-tests.* && -d "${workDir}" ]]; then
        if [[ "${keepWork}" == "YES" ]]; then
            say "Work directory kept: ${workDir}"
        else
            chflags -R nouchg "${workDir}" 2>/dev/null
            rm -rf "${workDir}"
        fi
    fi

    print ""
    print -r -- "Results log: ${resultsLog}"
    exit "${exitStatus}"
}

function scriptVersionOf() {
    sed -n 's/^scriptVersion="\([^"]*\)".*/\1/p' "${1}" 2>/dev/null | head -n 1
}

function changelogTopHeading() {
    grep -m 1 -E '^### Version ' "${changelogPath}" 2>/dev/null
}

# --release needs the exact heading; a --prerelease heading may add " (Unreleased)" or a date
function changelogHeadingMatchesRelease() {
    local topHeading="${1}"

    [[ "${topHeading}" == "### Version ${releaseVersion}" ]] && return 0
    [[ "${releaseKind}" == "prerelease" && "${topHeading}" == "### Version ${releaseVersion} ("*")" ]]
}

function gitRun() {
    "${gitBinary}" -c safe.directory="${repoRoot}" -C "${repoRoot}" "$@" 2>/dev/null
}

function repositorySnapshot() {
    [[ "${gitCheckout}" == "YES" ]] || return 0
    gitRun status --porcelain --ignored
    ls -lT "${repoRoot}/Artifacts" 2>/dev/null
}

function parseArguments() {
    while (( $# > 0 )); do
        case "${1}" in
            --unit         ) integrationRequested="NO" ;;
            --integration  ) integrationRequested="YES" ;;
            --skip-dialogs ) skipDialogs="YES" ;;
            --keep         ) keepWork="YES" ;;
            --filter )
                [[ -n "${2:-}" ]] || banner STOP "Missing --filter value" "--filter was given without text." "The run cannot tell which tests to keep." "sudo zsh Tests/runTests.zsh --filter starter" 64
                testFilter="${2}"
                shift
                ;;
            --release )
                [[ "${2:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || banner STOP "Invalid --release value" "--release needs a version such as 5.4.0 (got '${2:-}')." "The release check compares every scriptVersion and the CHANGELOG heading to this value." "sudo zsh Tests/runTests.zsh --integration --release 5.4.0" 64
                [[ -z "${releaseKind}" ]] || banner STOP "Both --release and --prerelease given" "Only one version check can run per invocation." "Each flag accepts a different version form and CHANGELOG heading." "Pick one: --release <x.y.z> or --prerelease <x.y.zbN>" 64
                releaseVersion="${2}"
                releaseKind="release"
                shift
                ;;
            --prerelease )
                [[ "${2:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+b[0-9]+$ ]] || banner STOP "Invalid --prerelease value" "--prerelease needs a beta version such as 5.4.0b1 (got '${2:-}')." "The prerelease check compares every scriptVersion and the CHANGELOG heading to this value." "sudo zsh Tests/runTests.zsh --integration --prerelease 5.4.0b1" 64
                [[ -z "${releaseKind}" ]] || banner STOP "Both --release and --prerelease given" "Only one version check can run per invocation." "Each flag accepts a different version form and CHANGELOG heading." "Pick one: --release <x.y.z> or --prerelease <x.y.zbN>" 64
                releaseVersion="${2}"
                releaseKind="prerelease"
                shift
                ;;
            --help|-h )
                printUsage
                exit 0
                ;;
            * )
                banner STOP "Unknown option '${1}'" "runTests.zsh does not recognize '${1}'." "Unknown options could hide a typo such as --integraton, so nothing ran." "sudo zsh Tests/runTests.zsh --help" 64
                ;;
        esac
        shift
    done
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Preflight
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function preflightRoot() {
    if [[ "$(id -u)" -ne 0 ]]; then
        banner STOP "Run as root" "The suite was started as '$(id -un)', not root." "Tests read root-only DDM state, write root-owned fixtures, and the integration tier deploys a LaunchDaemon." "sudo zsh Tests/runTests.zsh${runArguments:+ ${runArguments}}" 64
    fi
}

function preflightCheckout() {
    local requiredPath=""
    local -a missingPaths=()

    for requiredPath in "${rdPath}" "${ldmPath}" "${asmPath}" "${repoRoot}/Resources" "${changelogPath}"; do
        [[ -e "${requiredPath}" ]] || missingPaths+=( "${requiredPath:t}" )
    done

    if (( ${#missingPaths[@]} > 0 )); then
        banner STOP "Not a full DDM OS Reminder checkout" "Missing next to Tests/: ${(j:, :)missingPaths} (in ${repoRoot})." "The suite tests the scripts in the checkout it lives in; copying only Tests/ leaves nothing to test." "git clone -b development ${repositoryURL} && sudo zsh DDM-OS-Reminder/Tests/runTests.zsh" 69
    fi
}

function preflightGit() {
    local upstreamBehind=""
    local fetchAge="never fetched"
    local fetchEpoch=""
    local uncommitted=""

    gitBinary="$(command -v git 2>/dev/null)"
    if [[ -n "${gitBinary}" && "${gitBinary}" == "/usr/bin/git" ]] && ! xcode-select -p >/dev/null 2>&1; then
        gitBinary=""
    fi

    if [[ -z "${gitBinary}" || ! -e "${repoRoot}/.git" ]] || ! gitRun rev-parse --git-dir >/dev/null; then
        gitCheckout="NO"
        banner WARN "Not a git checkout" "'${repoRoot}' is not a usable git checkout (or git is unavailable)." "Results can't be tied to a commit, and the repo-clean guard is skipped." "Use a git clone: git clone -b development ${repositoryURL}"
        return
    fi

    gitCheckout="YES"
    gitBranch="$(gitRun rev-parse --abbrev-ref HEAD)"
    gitCommit="$(gitRun rev-parse --short HEAD)"

    if [[ "${gitBranch}" != "development" ]]; then
        banner WARN "Branch is '${gitBranch}', not development" "The checkout is on '${gitBranch}'." "Pre-release testing targets the development branch." "cd '${repoRoot}' && git switch development && git pull"
    fi

    if [[ -f "${repoRoot}/.git/FETCH_HEAD" ]]; then
        fetchEpoch="$(stat -f %m "${repoRoot}/.git/FETCH_HEAD" 2>/dev/null)"
        [[ "${fetchEpoch}" == <-> ]] && fetchAge="last fetch $(( ($(date +%s) - fetchEpoch) / 3600 )) hour(s) ago"
    fi

    upstreamBehind="$(gitRun rev-list --count "HEAD..origin/${gitBranch}")"
    if [[ "${upstreamBehind}" == <-> ]] && (( upstreamBehind > 0 )); then
        banner WARN "Behind origin/${gitBranch}" "The checkout is ${upstreamBehind} commit(s) behind origin/${gitBranch} (${fetchAge}; no automatic fetch)." "You would be testing code that is already out of date." "cd '${repoRoot}' && git pull"
    else
        logOnly "Upstream check: not behind origin/${gitBranch} (${fetchAge}; no automatic fetch)."
    fi

    uncommitted="$(gitRun status --porcelain --untracked-files=no)"
    if [[ -n "${uncommitted}" ]]; then
        banner WARN "Uncommitted changes" "The checkout has uncommitted changes to tracked files ($(print -r -- "${uncommitted}" | wc -l | tr -d ' ') path(s))." "Results reflect local edits, not commit ${gitCommit}." "Commit, stash, or re-clone, then rerun"
    fi
}

function preflightVersions() {
    local asmVersion="$(scriptVersionOf "${asmPath}")"
    local ldmVersion="$(scriptVersionOf "${ldmPath}")"
    local rdVersion="$(scriptVersionOf "${rdPath}")"
    local topHeading="$(changelogTopHeading)"
    local -a mismatches=()

    if [[ "${asmVersion}" != "${ldmVersion}" || "${ldmVersion}" != "${rdVersion}" ]]; then
        banner STOP "scriptVersion differs between scripts" "assemble.zsh=${asmVersion:-missing}, launchDaemonManagement.zsh=${ldmVersion:-missing}, reminderDialog.zsh=${rdVersion:-missing}." "assemble.zsh refuses to build mismatched versions, so nothing downstream can be trusted." "Align scriptVersion in assemble.zsh, launchDaemonManagement.zsh, and reminderDialog.zsh" 69
    fi

    if [[ -n "${releaseVersion}" ]]; then
        [[ "${asmVersion}" == "${releaseVersion}" ]] || mismatches+=( "assemble.zsh scriptVersion=${asmVersion}" )
        [[ "${ldmVersion}" == "${releaseVersion}" ]] || mismatches+=( "launchDaemonManagement.zsh scriptVersion=${ldmVersion}" )
        [[ "${rdVersion}" == "${releaseVersion}" ]] || mismatches+=( "reminderDialog.zsh scriptVersion=${rdVersion}" )
        changelogHeadingMatchesRelease "${topHeading}" || mismatches+=( "CHANGELOG.md top heading='${topHeading}'" )
        if (( ${#mismatches[@]} > 0 )); then
            if [[ "${releaseKind}" == "prerelease" ]]; then
                banner STOP "Prerelease ${releaseVersion} does not match the checkout" "${(j:; :)mismatches}." "A prerelease run must test exactly the beta being deployed (the version test is skipped, not reported as a FAIL)." "Set each file listed above to ${releaseVersion} (CHANGELOG heading '### Version ${releaseVersion}', optionally followed by ' (Unreleased)' or a date), then rerun with --prerelease ${releaseVersion}" 69
            else
                banner STOP "Release ${releaseVersion} does not match the checkout" "${(j:; :)mismatches}." "A release run must test exactly the versions being shipped (the version test is skipped, not reported as a FAIL)." "Set each file listed above to ${releaseVersion} (CHANGELOG heading '### Version ${releaseVersion}', no '(Unreleased)'), then rerun with --release ${releaseVersion}" 69
            fi
        fi
    elif [[ "${topHeading}" == *"(Unreleased)"* ]]; then
        banner INFO "Pre-release build" "CHANGELOG top heading is '${topHeading#\#\#\# }'; scripts are ${rdVersion}." "The final pre-release check (workflow step 6) has not run yet." "Bump scriptVersion and the CHANGELOG heading, then: sudo zsh Tests/runTests.zsh --integration --release <version> (a beta such as 5.4.0b1: --prerelease <version>)"
    fi
}

function preflightProductionDaemon() {
    if launchctl print "system/${productionDaemonLabel}" >/dev/null 2>&1; then
        productionDaemonLoaded="YES"
        banner INFO "Production daemon loaded" "'${productionDaemonLabel}' is loaded on this Mac." "The suite never touches it; integration deploys ${testRdnn} in Script mode only." "None"
    else
        productionDaemonLoaded="NO"
        banner INFO "Production daemon not loaded" "'${productionDaemonLabel}' is not loaded on this Mac." "Workflow step 7 (upgrade-path check) needs production 5.3.0 deployed through your MDM first." "Deploy production 5.3.0 before step 7"
    fi
}

function preflightIntegration() {
    local consoleUser="$(consoleUserName)"
    local livePersistencePlist="/var/db/softwareupdate/SoftwareUpdateDDMStatePersistence.plist"
    local liveFingerprint=""

    if ! consoleUserIsReady; then
        if [[ "${skipDialogs}" == "YES" ]]; then
            consoleDependentScenarios="NO"
            banner WARN "No console user" "The console user is '${consoleUser:-none}'." "dor.zsh waits for a logged-in user, so console-dependent scenarios are skipped." "Log in as a standard user and rerun for full coverage"
        else
            banner STOP "No console user" "The console user is '${consoleUser:-none}'." "Integration scenarios run dor.zsh and show dialogs, which need a logged-in user." "Log in as a standard user and rerun (or add --skip-dialogs)" 69
        fi
    fi

    if [[ ! -x "/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/dialogcli" ]]; then
        banner WARN "swiftDialog not installed" "'/Library/Application Support/Dialog/Dialog.app' is missing." "launchDaemonManagement.zsh will download and install swiftDialog system-wide during the test deploy." "Install swiftDialog first if that is not wanted"
    fi

    if testRdnnLeftoversPresent; then
        banner WARN "Leftovers from an earlier run" "Found ${testRdnn} files or a loaded ${testRdnn}.dor daemon (probably an aborted run)." "Leftover state would skew the scenarios; it is removed now (test RDNN only)." "None (informational)"
        teardownTestRdnn
    fi

    if ! liveFingerprint="$(persistencePlistFingerprint "${livePersistencePlist}")" || [[ "${liveFingerprint}" == "d41d8cd98f00b204e9800998ecf8427e" ]]; then
        banner WARN "No live DDM declaration" "'${livePersistencePlist}' is unreadable or lists zero declarations." "Live heartbeat realism is reduced; fixture-based tests still run." "Have the MDM send a DDM enforcement declaration to this Mac (workflow step 1)"
    fi
}

function writeLogHeader() {
    local macOSVersion="$(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
    local preflightLog="${workDir}/preflight.log"

    # Preflight banners were logged before the header existed; keep them after it
    mv "${resultsLog}" "${preflightLog}" 2>/dev/null || : > "${preflightLog}"
    : > "${resultsLog}"
    chmod 644 "${resultsLog}" 2>/dev/null
    logOnly "DDM OS Reminder test suite"
    logOnly "Date:               $(date '+%Y-%m-%d %H:%M:%S %z')"
    logOnly "macOS:              ${macOSVersion}"
    logOnly "Checkout:           ${repoRoot}"
    logOnly "scriptVersion:      $(scriptVersionOf "${rdPath}")"
    if [[ "${gitCheckout}" == "YES" ]]; then
        logOnly "Git:                ${gitBranch} @ ${gitCommit}"
    else
        logOnly "Git:                not a git checkout"
    fi
    logOnly "Flags:              ${originalArguments}"
    logOnly "Production daemon:  ${productionDaemonLabel} loaded=${productionDaemonLoaded}"
    logOnly "Work directory:     ${workDir}"
    logOnly ""
    cat "${preflightLog}" >> "${resultsLog}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Test Execution
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function sourceTier() {
    local tier="${1}"
    local testFile=""

    for testFile in "${testsRoot}/${tier}"/[0-9][0-9]-*.zsh(N); do
        testTier="${tier}"
        testGroup="${tier}/${${testFile:t:r}#[0-9][0-9]-}"
        source "${testFile}"
    done
}

function runTier() {
    local tier="${1}"
    local index=0
    local label=""
    local testRc=0
    local detailLine=""
    local skipReason=""

    for (( index = 1; index <= ${#registeredCommands[@]}; index++ )); do
        [[ "${registeredTiers[index]}" == "${tier}" ]] || continue
        label="[${registeredGroups[index]}] ${registeredDescriptions[index]}"

        if [[ -n "${testFilter}" && "${label}" != *"${testFilter}"* ]]; then
            (( filteredCount++ ))
            continue
        fi

        testDir="${workDir}/t/$(printf '%03d' "${index}")"
        testFailFile="${testDir}.fail"
        testSkipFile="${testDir}.skip"
        mkdir -p "${testDir}"

        # A nonzero status here means the test (or code under test) exited early, not a failed assert
        ( cd "${testDir}" && eval "${registeredCommands[index]}"; exit 0 ) > "${testDir}.out" 2>&1
        testRc=$?

        if [[ -s "${testSkipFile}" && ! -s "${testFailFile}" ]]; then
            skipReason="$(< "${testSkipFile}")"
            say "SKIP  ${label} (${skipReason})"
            (( skipCount++ ))
        elif [[ -s "${testFailFile}" || ${testRc} -ne 0 ]]; then
            say "FAIL  ${label}"
            if [[ -s "${testFailFile}" ]]; then
                while IFS= read -r detailLine; do
                    say "        ${detailLine}"
                done < "${testFailFile}"
            fi
            (( testRc != 0 )) && say "        test aborted with exit status ${testRc}; output: ${testDir}.out"
            (( failCount++ ))
            [[ "${tier}" == "unit" ]] && (( unitFailCount++ ))
        else
            say "PASS  ${label}"
            (( passCount++ ))
        fi
    done
}

function runRepositoryGuard() {
    local repoStatusAfter=""

    if [[ "${gitCheckout}" != "YES" ]]; then
        say "SKIP  [guard] repository unchanged by the run (not a git checkout)"
        (( skipCount++ ))
        return
    fi

    repoStatusAfter="$(repositorySnapshot)"
    if [[ "${repoStatusAfter}" == "${repoStatusBefore}" ]]; then
        say "PASS  [guard] repository unchanged by the run"
        (( passCount++ ))
    else
        say "FAIL  [guard] repository unchanged by the run"
        say "        git status --porcelain --ignored (or Artifacts/) changed during the run; the suite must never write into the checkout"
        diff <(print -r -- "${repoStatusBefore}") <(print -r -- "${repoStatusAfter}") | sed 's/^/        /' | while IFS= read -r detailLine; do say "${detailLine}"; done
        (( failCount++ ))
    fi
}

function printSummary() {
    local attentionItem=""

    if (( ${#attentionItems[@]} > 0 )); then
        say ""
        say "Attention (repeated from above):"
        for attentionItem in "${attentionItems[@]}"; do
            say "  - ${attentionItem}"
        done
    fi

    say ""
    say "${passCount} passed, ${failCount} failed, ${skipCount} skipped$( (( filteredCount > 0 )) && print -r -- ", ${filteredCount} filtered out")"
}



####################################################################################################
#
# Program
#
####################################################################################################

trap finishRun EXIT

print -r -- "Run started $(date '+%Y-%m-%d %H:%M:%S %z') as '$(id -un)'; flags: ${originalArguments}" > "${resultsLog}" 2>/dev/null
parseArguments "$@"

preflightRoot
preflightCheckout
preflightGit
preflightVersions
preflightProductionDaemon
[[ "${integrationRequested}" == "YES" ]] && preflightIntegration

workDir="$( mktemp -d /var/tmp/dor-tests.XXXXXX )" || banner STOP "Unable to create work directory" "mktemp -d /var/tmp/dor-tests.XXXXXX failed." "Every test writes only inside that directory." "Check free space and permissions on /var/tmp" 73
chmod 755 "${workDir}"
stubDir="${workDir}/stubs"
extractDir="${workDir}/extracted"
createStubs

repoStatusBefore="$(repositorySnapshot)"

writeLogHeader
say "Testing checkout: ${repoRoot} ($( [[ "${gitCheckout}" == "YES" ]] && print -r -- "${gitBranch} @ ${gitCommit}" || print -r -- "not a git checkout" ))"
say ""

# Unit tier
say "== Unit tier =="
sourceTier unit
runTier unit

# Integration tier
if [[ "${integrationRequested}" == "YES" ]]; then
    if (( unitFailCount > 0 )); then
        runRepositoryGuard
        printSummary
        banner STOP "Integration not run" "${unitFailCount} unit test(s) failed." "Integration deploys real files; unit failures must be understood first." "Fix the unit failures first; bring back ${resultsLog}" 1
    fi

    say ""
    say "== Integration tier (${testRdnn}; Script mode only; production daemon untouched) =="
    integrationStarted="YES"
    sourceTier integration
    runTier integration
fi

say ""
runRepositoryGuard
printSummary

if (( failCount > 0 )); then
    banner STOP "${failCount} test(s) failed" "See the FAIL lines above (also in the results log)." "A failure is either a real defect or a test that needs updating; either way the pre-release is blocked." "Bring back ${resultsLog}; rerun with --keep to keep the work folder" 1
fi

if [[ "${integrationRequested}" != "YES" ]]; then
    banner INFO "Unit tier passed" "All unit tests passed." "The integration tier still has to run on this Mac." "sudo zsh Tests/runTests.zsh --integration"
elif [[ -z "${releaseVersion}" ]]; then
    banner INFO "Unit and integration tiers passed" "All tests passed without --release." "Workflow steps 6 and 7 remain." "Step 6: bump scriptVersion, then sudo zsh Tests/runTests.zsh --integration --release <version>; step 7: deploy through the MDM over 5.3.0"
elif [[ "${releaseKind}" == "prerelease" ]]; then
    banner INFO "Prerelease ${releaseVersion} passed" "All tests passed with --integration --prerelease ${releaseVersion}." "A beta pass is not the final release check." "Deploy the ${releaseVersion} artifact to test Macs through the MDM over 5.3.0; before shipping, bump to the final version and rerun with --release"
else
    banner INFO "Release ${releaseVersion} passed" "All tests passed with --integration --release ${releaseVersion}." "Only the upgrade-path check remains." "Step 7: deploy the ${releaseVersion} artifact through the MDM over 5.3.0 and confirm the first heartbeat seeds LastDeclarationFingerprint"
fi

exit 0
