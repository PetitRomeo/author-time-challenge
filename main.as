// Author Time Challenge
//
// Open the "Challenge" button in the footer, adjust the options, and press "Start". You have a time limit to score as
// many author times as you can on random tracks:
//   * Author time on a track:  +1 point, and the next track starts after a short delay (3 seconds by default).
//                              The clock is paused during that delay.
//   * Gold (but not author):   you may skip this track for free, or keep trying for the author time.
//                              The gold time is computed from the author time (see GoldTime), so no website is needed.
//   * Skip key or button:      loads the next random track. It costs one free skip, unless you got gold on this track.
//   * No free skips left:      you must get the author time to move on (or let the clock run out).
// The clock only runs while you are on a track: loading or downloading a track does not cost you time.
// If a track fails to open, or you leave it, the "Back to race" button in the menu gets you going again.

[Setting name="Time limit (minutes)" min=1 max=180 description="How long the challenge lasts."]
int TimeLimitMinutes = 10;

[Setting name="Free skips" min=0 max=50 description="Skips you can use on any track, even without gold."]
int FreeSkips = 3;

[Setting name="Track pool" choices="Game tracks + subscribed workshop maps|Game tracks + any workshop map" description="Subscribed: only your own subscribed workshop maps that are already on your computer (any that would need a download are skipped). Any workshop map: top-rated workshop maps, which Steam may need to download first."]
string TrackPool = "Game tracks + subscribed workshop maps";

[Setting name="Workshop map limit" description="How many maps of the workshop list can be picked. The list is the top-rated maps (or your subscribed maps), best first, so 500 means only the 500 best. Type any number, at least 1."]
int WorkshopCap = 5000;

[Setting name="Game track share (%)" min=0 max=100 description="Chance that a pick is a game track when using 'any workshop map'. 15 means 15% game tracks, the rest workshop maps. 0 = workshop maps only, 100 = game tracks only. Not used for subscribed maps, where every track has the same chance."]
int OfficialShare = 15;

[Setting name="Skip key code" hidden]
int SkipKeyCode = int(Input::K);         // Set from the key box in the Challenge menu.

[Setting name="Delay after author time (seconds)" min=0 max=10 description="How long to wait after an author time before the next track starts. The clock is paused during this delay."]
float AuthorDelay = 3;

// ---------------------------------------------------------------------------------------------------------------------
const int S_IDLE = 0, S_PREPARE = 1, S_PICKWAIT = 2, S_LOADING = 3, S_RACING = 4, S_AUTHOR = 5, S_RETRY = 6;

// Gold medal formula, worked out from the medal rows of 20+ workshop maps (author time -> gold/silver/bronze, seconds).
// Gold is the author time x 1.06 (silver x 1.2, bronze x 1.6), in whole seconds, and which way it is rounded depends on
// when the map was published:
//   * Recent maps (published after the game changed, around mid September 2026): rounded UP, like Trackmania.
//        3.649 -> 4/5/6    5.736 -> 7/7/10    20.491 -> 22/25/33    27.022 -> 29/33/44    93.365 -> 99/113/150
//      155.288 -> 165/187/249   198.191 -> 211/238/318   283.333 -> 301/341/454
//   * Older maps: rounded to the NEAREST second.
//        4.297 -> 5/5/7    8.911 -> 9/11/14    12.426 -> 13/15/20    31.462 -> 33/38/50    44.829 -> 48/54/72
//      207.025 -> 219/248/331
// Every map checked fits one of the two exactly. The exact day the game changed is not known (it lies between the
// 24 and 35 days old maps checked), so a map published close to OLD_FORMULA_BEFORE could be off by a second.
const double GOLD_MULTIPLIER = 1.06;
const int64 OLD_FORMULA_BEFORE = 1789732800;     // 2026-09-18 12:00 UTC, in seconds since 1970.

const int WORKSHOP_PAGE = 50;            // Maps per workshop results page.
const int RECENT_KEEP = 25;              // A track is not repeated until this many others have been played.
const double STUCK_SECONDS = 20;         // After this long without progress, the Back to race button appears.

const array<string> POOL_CHOICES = {"Game tracks + subscribed workshop maps", "Game tracks + any workshop map"};

// The menu (a window above the footer).
UI::FooterButton@ footerButton;
UI::Window@ menu;
UI::TextInput@ timeInput;
UI::TextInput@ skipsInput;
UI::Dropdown@ poolDropdown;
UI::Button@ keyButton;                   // The key box: click it, then press the key to use.
UI::Button@ hideTimerButton;
bool listeningKey = false;
int keyListenDelay = 0;
UI::TextInput@ delayInput;
UI::TextInput@ capInput;
UI::Slider@ shareSlider;
UI::Text@ shareText;
bool shareDragging = false;
UI::Text@ statusText;
UI::Text@ bestText;
UI::Button@ startButton;
UI::Button@ skipButton;
UI::Button@ stopButton;
UI::Button@ backButton;
UI::Button@ closeButton;
bool menuOpen = false;
float menuFooter = -1;
int pendingStart = 0;                    // Frames until typed values have been committed and the challenge starts.

// Indexes of this plugin's settings in the Settings:: list.
int idxTime = -1, idxSkips = -1, idxPool = -1, idxKey = -1, idxDelay = -1, idxCap = -1, idxShare = -1;

// The HUD during a challenge.
UI::Window@ hud;
UI::Text@ timeText;
UI::Text@ scoreText;
UI::Text@ skipsText;
UI::Text@ trackText;
UI::Text@ messageText;

array<string> officialLevels;
double nextOfficialCheck = 0;

bool active = false;
int state = S_IDLE;
int score = 0;
int skipsLeft = 0;
double timeLeft = 0;
double lastTimerUpdate = 0;
bool timerUpdateReady = false;

// Track picking.
bool wsSubscribed = true;
int wsTotal = 0;
int pageQuery = -1;                      // The first results page, kept for the whole challenge.
int pickQuery = -1;
int wantOffset = 0;
double stateSince = 0;
double retryAt = 0;
int loadFails = 0;
array<string> recent;
array<string> rejected;                  // Workshop ids that turned out not to be downloaded yet.
string currentId = "";
string loadingTitle = "";
int requestedMap = -1;
bool autoOpened = false;                 // The menu opened itself once for a problem.

// The current track.
string trackKey = "";
double authorTime = 0;
double activeSeconds = 0;
double lastElapsed = 0;
bool goldEarned = false;
bool finishSeen = false;
bool finishHandled = false;
double finishAt = 0;
double advanceAt = 0;
double lostSince = -1;                   // Since when the player has not been on the track.

string messageLine = "";
double messageUntil = 0;
bool resultShown = false;              // The finished challenge's timer window stays until the Hide timer button is pressed.
string resultLine = "";

uint64 rngState = 88172645463325252;

// --- Small helpers ---------------------------------------------------------------------------------------------------
void Reseed()
{
    rngState ^= uint64(Host::Time() * 1000.0) * 2654435761;
    if (rngState == 0)
        rngState = 88172645463325252;
}

int Rand(int n)
{
    if (n <= 1)
        return 0;
    rngState ^= rngState << 13;
    rngState ^= rngState >> 7;
    rngState ^= rngState << 17;
    return int(rngState % uint64(n));
}

string Pad(int v, int width)
{
    string s = "" + v;
    while (int(s.length()) < width)
        s = "0" + s;
    return s;
}

string FormatTime(double t)
{
    if (t < 0)
        t = 0;
    int ms = int(t * 1000.0 + 0.5);
    return "" + (ms / 60000) + ":" + Pad((ms / 1000) % 60, 2) + "." + Pad(ms % 1000, 3);
}

string FormatClock(double t)
{
    if (t < 0)
        t = 0;
    int total = int(Math::ceil(t));
    return "" + (total / 60) + ":" + Pad(total % 60, 2);
}

bool IsRecent(const string &in id)
{
    return recent.find(id) >= 0;
}

void Remember(const string &in id)
{
    if (id == "" || IsRecent(id))
        return;
    recent.insertLast(id);
    while (int(recent.length()) > RECENT_KEEP)
        recent.removeAt(0);
}

void Notify(const string &in message)
{
    messageLine = message;
    messageUntil = Host::Time() + 5;
    Log::Info(message);
}

Input::Key SkipKey()
{
    return Input::Key(SkipKeyCode);
}

string BestKey()
{
    return "best:" + TimeLimitMinutes + ":" + FreeSkips + ":" + (TrackPool.findFirst("subscribed") >= 0 ? "sub" : "any");
}

int BestScore()
{
    return int(parseInt(Storage::Get(BestKey(), "0")));
}

// The game's own tracks are only listed on the main menu, so they are noted whenever they are seen.
void CacheOfficial()
{
    // Tracks::Official() can be incomplete during an early menu snapshot. Keep polling
    // instead of freezing the first non-empty result, and merge each newly seen track.
    if (Host::Time() < nextOfficialCheck)
        return;
    nextOfficialCheck = Host::Time() + 1;

    array<string>@ levels = Tracks::Official();
    if (levels is null || levels.length() == 0)
        return;

    bool changed = false;
    for (uint i = 0; i < levels.length(); i++)
    {
        if (levels[i] != "" && officialLevels.find(levels[i]) < 0)
        {
            officialLevels.insertLast(levels[i]);
            changed = true;
        }
    }

    if (changed)
    {
        int circuitCount = 0, collabCount = 0, trialCount = 0, otherCount = 0;
        for (uint i = 0; i < officialLevels.length(); i++)
        {
            string group = Tracks::Group(officialLevels[i]);
            if (group.findFirst("season") == 0)
                circuitCount++;
            else if (group == "collabs")
                collabCount++;
            else if (group == "trials")
                trialCount++;
            else
                otherCount++;
        }
        Log::Info("Challenge: game-track catalog now has " + officialLevels.length()
            + " tracks (circuits: " + circuitCount + ", collabs: " + collabCount
            + ", trials: " + trialCount + ", other: " + otherCount + ").");
    }
}

// The gold time of a track in seconds, from its author time (see the formula above). `published` is when the map was
// published (seconds since 1970), or 0 if unknown: the current rule, rounding up, is used then, and for the game's own tracks.
double GoldTime(double author, int64 published)
{
    double x = author * GOLD_MULTIPLIER;
    if (published > 0 && published < OLD_FORMULA_BEFORE)
        return Math::floor(x + 0.5);
    return Math::ceil(x - 0.000001);        // the small subtraction keeps an exact whole second from rounding up by float error
}

// The gold time of the track being raced.
double GoldFor(double author)
{
    int64 published = 0;
    if (currentId.substr(0, 2) == "w:")
        published = Workshop::Created(currentId.substr(2));
    return GoldTime(author, published);
}

// A page of the workshop pool: the player's own subscribed maps, or the top-rated maps of the whole workshop.
int WorkshopQuery(int page)
{
    if (wsSubscribed)
        return Workshop::FindList("subscribed", "", "new", page);
    return Workshop::Find("", "top", page);
}

// --- Starting and ending ---------------------------------------------------------------------------------------------
void StartChallenge()
{
    if (active)
        return;
    nextOfficialCheck = 0;
    CacheOfficial();
    if (officialLevels.length() == 0)
    {
        Notify("Open the main menu first, so the game's track list is loaded.");
        return;
    }
    Reseed();
    active = true;
    menuOpen = false;
    score = 0;
    skipsLeft = FreeSkips;
    timeLeft = TimeLimitMinutes * 60.0;
    lastTimerUpdate = Host::Time();
    timerUpdateReady = true;
    recent.resize(0);
    loadFails = 0;
    autoOpened = false;
    lostSince = -1;
    resultShown = false;
    wsSubscribed = TrackPool.findFirst("subscribed") >= 0;
    rejected.resize(0);
    wsTotal = 0;
    pickQuery = -1;
    state = S_PREPARE;
    stateSince = Host::Time();
    pageQuery = WorkshopQuery(1);
    if (pageQuery < 0)
        Log::Warn("Challenge: the workshop search is not available, using game tracks only.");
    Notify("Challenge started: " + TimeLimitMinutes + " min, " + FreeSkips + " free skips.");
}

void EndChallenge(bool timeUp)
{
    if (!active)
        return;
    active = false;
    state = S_IDLE;
    int best = BestScore();
    bool record = score > best;
    if (record)
        Storage::Set(BestKey(), "" + score);
    resultLine = timeUp ? "Time's up!  " : "Challenge stopped.  ";
    resultLine += "Score: " + score;
    if (record)
        resultLine += "  (new best!)";
    else
        resultLine += "  (best: " + best + ")";
    resultShown = true;
    Notify(resultLine);
}

// --- Picking the next track --------------------------------------------------------------------------------------------
void StartLoading(const string &in id, const string &in title)
{
    currentId = id;
    loadingTitle = title;
    requestedMap = Host::MapNumber();
    stateSince = Host::Time();
    state = S_LOADING;
}

void OpenFailed(const string &in what)
{
    loadFails++;
    Log::Warn("Challenge: could not open " + what + " (" + Tracks::OpenState() + ").");
    if (loadFails >= 3)
    {
        Notify("The next track will not open. Press Back to race in the Challenge menu.");
        if (!autoOpened)
        {
            autoOpened = true;
            menuOpen = true;
        }
    }
    retryAt = Host::Time() + 2;
    state = S_RETRY;
    stateSince = Host::Time();
}

void OpenOfficial(const string &in level)
{
    string title = Tracks::Title(level);
    // Capture the old map before opening: an official track can advance MapNumber()
    // inside Tracks::Open(), unlike a workshop map that may spend time downloading.
    int previousMap = Host::MapNumber();
    if (Tracks::Open(level))
    {
        currentId = "o:" + level;
        loadingTitle = title == "" ? string(level) : title;
        requestedMap = previousMap;
        stateSince = Host::Time();
        state = S_LOADING;
    }
    else
        OpenFailed(level);
}

void OpenWorkshopTrack(const string &in id)
{
    string title = Workshop::Title(id);
    if (Tracks::OpenWorkshop(id))
        StartLoading("w:" + id, title == "" ? string("workshop map " + id) : title);
    else
        OpenFailed("workshop map " + id);
}

// Opens the map at wantOffset of a finished results page (or another from that page if it was played lately, or is
// known not to be downloaded). False if the page had nothing usable (nothing was opened).
bool OpenFromQuery(int query)
{
    int count = Workshop::Count(query);
    if (count <= 0)
        return false;
    for (int tries = 0; tries < 8; tries++)
    {
        int offset = (tries == 0 && wantOffset < count) ? wantOffset : Rand(count);
        string id = Workshop::Id(query, offset);
        if (id == "" || IsRecent("w:" + id) || rejected.find(id) >= 0)
            continue;
        OpenWorkshopTrack(id);
        return true;
    }
    return false;
}

void PickNext()
{
    int officialN = int(officialLevels.length());
    for (int attempt = 0; attempt < 8; attempt++)
    {
        bool useWorkshop = false;
        int index = 0;
        if (wsTotal > 0)
        {
            if (wsSubscribed)
            {
                int r = Rand(officialN + wsTotal);
                useWorkshop = r >= officialN;
                index = r - officialN;
            }
            else
            {
                int share = OfficialShare < 0 ? 0 : (OfficialShare > 100 ? 100 : OfficialShare);
                useWorkshop = Rand(100) >= share;
                index = Rand(wsTotal);
            }
        }
        if (!useWorkshop)
        {
            string level = officialLevels[Rand(officialN)];
            if (IsRecent("o:" + level) && attempt < 7)
                continue;
            OpenOfficial(level);
            return;
        }
        int page = index / WORKSHOP_PAGE + 1;
        wantOffset = index % WORKSHOP_PAGE;
        if (page == 1 && pageQuery >= 0)
        {
            if (OpenFromQuery(pageQuery))
                return;
            continue;
        }
        pickQuery = WorkshopQuery(page);
        if (pickQuery < 0)
            continue;
        state = S_PICKWAIT;
        stateSince = Host::Time();
        return;
    }
    OpenOfficial(officialLevels[Rand(officialN)]);
}

void AdvanceTrack()
{
    Remember(currentId);
    PickNext();
}

// Opens the track that was being raced again (after the player left it).
void ReopenCurrent()
{
    if (currentId.length() > 2)
    {
        string kind = currentId.substr(0, 2);
        string id = currentId.substr(2);
        if (kind == "o:")
            OpenOfficial(id);
        else
            OpenWorkshopTrack(id);
    }
    else
    {
        PickNext();
    }
}

// --- The run on a track ------------------------------------------------------------------------------------------------
void BeginTrack()
{
    state = S_RACING;
    trackKey = Race::TrackKey();
    authorTime = 0;
    activeSeconds = 0;
    lastElapsed = 0;
    goldEarned = false;
    finishSeen = false;
    finishHandled = false;
    loadFails = 0;
    autoOpened = false;
    lostSince = -1;
    Notify("Go! Every author time is +1.");
}

// The finish time from the run the host recorded. False while it is not there (yet).
bool FinishTime(double &out t)
{
    if (Runs::Count() <= 0 || !Runs::IsFinished(0) || Runs::TrackKey(0) != trackKey)
        return false;
    // The run must have ended around when the finish was seen, not be an earlier one.
    if (Runs::Age(0) > (Host::Time() - finishAt) + 0.75)
        return false;
    t = Runs::Time(0);
    return true;
}

void EvaluateFinish(double t)
{
    finishHandled = true;
    string why;
    if (Race::IsPractice() || Race::RunTainted(why))
    {
        string note = "That run does not count";
        if (why != "")
            note += " (" + why + ")";
        Notify(note + ".");
        return;
    }
    double author = authorTime > 0 ? authorTime : Race::AuthorTime();
    if (author <= 0)
    {
        Notify("No author time is known for this track.");
        return;
    }
    double goldAt = GoldFor(author);
    string goldNote = "Gold time: " + FormatTime(goldAt) + ".";
    if (t <= author + 0.0005)
    {
        score++;
        state = S_AUTHOR;
        advanceAt = Host::Time() + AuthorDelay;
        Notify("Author time! " + FormatTime(t) + "  (+1)");
    }
    else if (t <= goldAt + 0.0005)
    {
        goldEarned = true;
        Notify("Gold! " + FormatTime(t) + "  Skipping is free now. " + goldNote);
    }
    else
    {
        Notify("Finished in " + FormatTime(t) + ". Author time: " + FormatTime(author) + ". " + goldNote);
    }
}

void TickRacing(double dt, bool skipRequested)
{
    double a = Race::AuthorTime();
    if (a > 0)
        authorTime = a;
    if (Race::IsActive())
    {
        activeSeconds += dt;
        double e = Runs::Elapsed();
        if (e >= 0)
            lastElapsed = e;
    }

    // A track without an author time can never be scored, so move on for free.
    if (authorTime <= 0 && activeSeconds > 5)
    {
        Notify("This track has no author time. Skipping it for free.");
        AdvanceTrack();
        return;
    }

    if (Race::IsComplete())
    {
        if (!finishSeen)
        {
            finishSeen = true;
            finishAt = Host::Time();
        }
        if (!finishHandled)
        {
            double t = 0;
            if (FinishTime(t))
                EvaluateFinish(t);
            else if (Host::Time() - finishAt > 1.5 && lastElapsed > 0)
                EvaluateFinish(lastElapsed);        // The host's record never showed up: use the last clock reading.
        }
        if (state != S_RACING)
            return;
    }
    else
    {
        finishSeen = false;
        finishHandled = false;                      // A new run on the same track.
    }

    if (skipRequested)
    {
        if (goldEarned)
        {
            Notify("Free skip (gold).");
            AdvanceTrack();
        }
        else if (skipsLeft > 0)
        {
            skipsLeft--;
            Notify("Skipped. " + skipsLeft + " free skip(s) left.");
            AdvanceTrack();
        }
        else
        {
            Notify("No free skips left. Get the author time!");
        }
    }
}

// True when the challenge is running but the player is not on its track (they left to a menu).
bool LostTrack()
{
    return active && state == S_RACING && lostSince >= 0 && Host::Time() - lostSince > 2;
}

// True when the challenge needs the player's help to carry on.
bool NeedsHelp()
{
    if (!active)
        return false;
    if (LostTrack() || state == S_RETRY)
        return true;
    return (state == S_LOADING || state == S_PICKWAIT) && Host::Time() - stateSince > STUCK_SECONDS;
}

void BackToRace()
{
    menuOpen = false;
    loadFails = 0;
    autoOpened = false;
    if (!active)
        return;
    if (LostTrack())
        ReopenCurrent();
    else
        PickNext();
}

void TickChallenge(double dt, bool skipRequested)
{
    // Measure the timer interval separately from frame dt. Always refresh the baseline,
    // including while picking/downloading/loading, so a long load can never be charged
    // to the challenge when the next update arrives.
    double now = Host::Time();
    double timerDt = 0;
    if (timerUpdateReady && now >= lastTimerUpdate)
        timerDt = now - lastTimerUpdate;
    lastTimerUpdate = now;
    timerUpdateReady = true;

    // The clock runs only while racing on a track; loading states discard their elapsed time, and so does the
    // delay after an author time (S_AUTHOR), which is a pause.
    if (state == S_RACING || state == S_AUTHOR)
    {
        if (Race::OnTrack())
        {
            lostSince = -1;
            if (state == S_RACING)
            {
                timeLeft -= timerDt;
                if (timeLeft <= 0)
                {
                    timeLeft = 0;
                    EndChallenge(true);
                    return;
                }
            }
        }
        else if (lostSince < 0)
        {
            lostSince = Host::Time();
        }
        else if (LostTrack() && !autoOpened)
        {
            autoOpened = true;
            menuOpen = true;
            Notify("You left the track. Press Back to race to carry on.");
        }
    }

    if (state == S_PREPARE)
    {
        bool ready = pageQuery < 0;
        if (!ready)
        {
            string s = Workshop::State(pageQuery);
            if (s == "done")
            {
                wsTotal = Workshop::Total(pageQuery);
                int cap = WorkshopCap < 1 ? 1 : WorkshopCap;
                if (wsTotal > cap)
                    wsTotal = cap;
                ready = true;
            }
            else if (s.findFirst("error") == 0 || s == "" || Host::Time() - stateSince > 20)
            {
                Log::Warn("Challenge: the workshop list is not available (" + s + "), using game tracks only.");
                wsTotal = 0;
                ready = true;
            }
        }
        if (ready)
        {
            Log::Info("Challenge: " + officialLevels.length() + " game tracks and " + wsTotal + " workshop maps in the pool.");
            PickNext();
        }
    }
    else if (state == S_PICKWAIT)
    {
        string s = Workshop::State(pickQuery);
        if (s == "done")
        {
            bool opened = OpenFromQuery(pickQuery);
            Workshop::Forget(pickQuery);
            pickQuery = -1;
            if (!opened)
            {
                retryAt = Host::Time() + 0.3;
                state = S_RETRY;
                stateSince = Host::Time();
            }
        }
        else if (s.findFirst("error") == 0 || s == "" || Host::Time() - stateSince > 20)
        {
            Workshop::Forget(pickQuery);
            pickQuery = -1;
            retryAt = Host::Time() + 0.5;
            state = S_RETRY;
            stateSince = Host::Time();
        }
    }
    else if (state == S_RETRY)
    {
        if (Host::Time() >= retryAt)
            PickNext();
    }
    else if (state == S_LOADING)
    {
        double waited = Host::Time() - stateSince;
        string open = Tracks::OpenState();
        if (wsSubscribed && currentId.substr(0, 2) == "w:" && waited > 0.3 && open == "downloading"
            && Host::MapNumber() == requestedMap)
        {
            // Only maps that are already on this computer are wanted: this one is not, so take another.
            rejected.insertLast(currentId.substr(2));
            Log::Info("Challenge: " + loadingTitle + " is not downloaded, picking another track.");
            Remember(currentId);
            PickNext();
        }
        else if (Host::MapNumber() != requestedMap && Race::OnTrack() && Race::TrackKey() != "")
            BeginTrack();
        else if (waited > 1 && open.findFirst("error") == 0)
            OpenFailed(loadingTitle);
        else if ((waited > 20 && open == "idle") || waited > 180)
            OpenFailed(loadingTitle);
    }
    else if (state == S_RACING)
    {
        if (Race::OnTrack())
            TickRacing(dt, skipRequested);
    }
    else if (state == S_AUTHOR)
    {
        if (Host::Time() >= advanceAt)
            AdvanceTrack();
    }
}

// --- Settings in the menu ----------------------------------------------------------------------------------------------
int FindSetting(const string &in pluginId, const string &in name)
{
    for (uint i = 0; i < Settings::Count(); i++)
        if (Settings::Plugin(i) == pluginId && Settings::Name(i) == name)
            return int(i);
    return -1;
}

string OwnId()
{
    string folder = Plugins::Folder();
    while (folder.length() > 0 && folder.substr(folder.length() - 1, 1) == "\\")
        folder = folder.substr(0, folder.length() - 1);
    int at = folder.findLast("\\");
    return at >= 0 ? folder.substr(at + 1) : folder;
}

int IndexOf(const array<string>@ list, const string &in value)
{
    for (uint i = 0; i < list.length(); i++)
        if (list[i] == value)
            return int(i);
    return 0;
}

// Puts the current setting values into the boxes.
void SyncMenu()
{
    timeInput.value = "" + TimeLimitMinutes;
    skipsInput.value = "" + FreeSkips;
    delayInput.value = formatFloat(AuthorDelay, "", 0, 1);
    capInput.value = "" + WorkshopCap;
    shareSlider.value = OfficialShare / 100.0f;
    shareText.text = "" + OfficialShare + "%";
    poolDropdown.selected = IndexOf(POOL_CHOICES, TrackPool);
    keyButton.label = listeningKey ? "Press a key..." : Input::Name(SkipKey());
}

void Commit(int index, const string &in text)
{
    if (index < 0 || !Settings::Set(uint(index), text))
    {
        Log::Warn("Challenge: that is not a valid value: " + text);
        SyncMenu();
    }
}

void ReadMenu()
{
    if (timeInput.Submitted())
        Commit(idxTime, timeInput.text);
    if (skipsInput.Submitted())
        Commit(idxSkips, skipsInput.text);
    if (delayInput.Submitted())
        Commit(idxDelay, delayInput.text);
    if (capInput.Submitted())
        Commit(idxCap, capInput.text);
    if (shareSlider.dragging)
    {
        shareDragging = true;
        shareText.text = "" + int(shareSlider.value * 100.0f + 0.5f) + "%";
    }
    else if (shareDragging)
    {
        shareDragging = false;              // Let go: save the value once.
        Commit(idxShare, "" + int(shareSlider.value * 100.0f + 0.5f));
    }
    if (poolDropdown.Changed())
        Commit(idxPool, POOL_CHOICES[poolDropdown.selected]);
    if (keyButton.Clicked() && !listeningKey)
    {
        listeningKey = true;
        keyListenDelay = 2;                 // Let the click that opened the box pass first.
        SyncMenu();
    }
}

void SubmitAll()
{
    timeInput.Submit();
    skipsInput.Submit();
    delayInput.Submit();
    capInput.Submit();
}

void UpdateMenu()
{
    float footer = UI::FooterHeight();
    if (menuOpen != menu.visible)
    {
        menu.visible = menuOpen;
        UI::SetCursorVisible(menuOpen);
        if (menuOpen)
            SyncMenu();
    }
    if (!menuOpen)
        return;
    if (footer != menuFooter)
    {
        menuFooter = footer;
        menu.SetOffset(0, -(footer + 10));
    }

    bool help = NeedsHelp();
    startButton.visible = !active;
    hideTimerButton.visible = !active && resultShown;
    skipButton.visible = active;
    stopButton.visible = active;
    backButton.visible = help;

    if (!active)
    {
        if (resultShown)
            statusText.text = resultLine;
        else
            statusText.text = "Ready. Set your options and press Start.";
    }
    else if (LostTrack())
        statusText.text = "You left the track. Press Back to race to carry on.";
    else if (help)
        statusText.text = "The next track did not open. Press Back to race to try again.";
    else
        statusText.text = "Running. Score: " + score + ", free skips left: " + skipsLeft + ".";
    bestText.text = "Best score with these options: " + BestScore();
}

// --- The HUD ---------------------------------------------------------------------------------------------------------
void UpdateHud()
{
    bool showResult = !active && resultShown;
    hud.visible = active || showResult;
    if (!hud.visible)
        return;

    if (active)
    {
        timeText.text = FormatClock(timeLeft);
        if (timeLeft < 30)
            timeText.SetColor(1, 0.15f, 0.15f, 1);
        else
            timeText.SetColor(1, 1, 1, 1);
        scoreText.text = "Score: " + score;
        if (goldEarned)
            skipsText.text = "Skip: free (gold)";
        else
            skipsText.text = "Free skips: " + skipsLeft;
        if (state == S_RACING || state == S_AUTHOR)
        {
            string name = Race::TrackName();
            string by = Race::TrackAuthor();
            if (by != "")
                name += "  by " + by;
            if (authorTime > 0)
                name += "   G: " + FormatTime(GoldFor(authorTime)) + "   A: " + FormatTime(authorTime);
            trackText.text = name;
        }
        else if (state == S_RETRY)
            trackText.text = "Could not open the next track...";
        else if (state == S_LOADING && Tracks::OpenState() == "downloading")
            trackText.text = "Downloading: " + loadingTitle;
        else
            trackText.text = "Loading: " + loadingTitle;
    }
    else
    {
        timeText.text = "0:00";
        timeText.SetColor(1, 0.15f, 0.15f, 1);
        scoreText.text = "Score: " + score;
        skipsText.text = "";
        trackText.text = "";
    }

    if (Host::Time() < messageUntil)
        messageText.text = messageLine;
    else if (showResult)
        messageText.text = resultLine;
    else
        messageText.text = "";
}

// --- Plugin callbacks --------------------------------------------------------------------------------------------------
UI::Text@ Label(const string &in text)
{
    UI::Text@ label = menu.AddText(text, 18);
    label.SetWidth(300);
    return label;
}

void Main()
{
    @footerButton = UI::AddFooterButton("Challenge");

    // The menu: roomy, with a heading, the options, then the status and buttons.
    @menu = UI::CreateWindow();
    menu.SetAnchor(0.5f, 1);
    menu.SetPivot(0.5f, 1);
    menu.SetOffset(0, -80);
    menu.SetPadding(30, 22);
    menu.SetRowGap(16);
    menu.SetCornerRadius(10);
    menu.SetBlocksClicks(true);
    menu.AddText("Author Time Challenge", 26);
    menu.NewRow();
    menu.AddText("Score as many author times as you can before the time runs out.", 15).SetColor(0.6f, 0.6f, 0.65f, 1);
    menu.NewRow();
    menu.AddText("", 4);
    menu.NewRow();

    Label("Time limit (minutes)");
    @timeInput = menu.AddTextInput(110, "10", 18);
    timeInput.clearOnSubmit = false;
    menu.NewRow();

    Label("Free skips");
    @skipsInput = menu.AddTextInput(110, "3", 18);
    skipsInput.clearOnSubmit = false;
    menu.NewRow();

    Label("Track pool");
    @poolDropdown = menu.AddDropdown(360);
    for (uint i = 0; i < POOL_CHOICES.length(); i++)
        poolDropdown.AddOption(POOL_CHOICES[i]);
    menu.NewRow();

    Label("Workshop map limit");
    @capInput = menu.AddTextInput(110, "5000", 18);
    capInput.clearOnSubmit = false;
    menu.NewRow();

    Label("Game track spawn rate");
    @shareSlider = menu.AddSlider(200);
    @shareText = menu.AddText("15%", 18);
    menu.NewRow();

    Label("Skip key");
    @keyButton = menu.AddButton(Input::Name(SkipKey()));
    menu.NewRow();

    Label("Delay after author time (s)");
    @delayInput = menu.AddTextInput(110, "3", 18);
    delayInput.clearOnSubmit = false;
    menu.NewRow();

    menu.AddText("Press Enter after typing a number. For the skip key, click its box, then press a key.", 14).SetColor(0.6f, 0.6f, 0.65f, 1);
    menu.NewRow();
    menu.AddText("", 4);
    menu.NewRow();
    @bestText = menu.AddText("", 17);
    menu.NewRow();
    @statusText = menu.AddText("", 18);
    menu.NewRow();
    menu.AddText("", 4);
    menu.NewRow();

    @startButton = menu.AddButton("Start");
    @skipButton = menu.AddButton("Skip track");
    @stopButton = menu.AddButton("Stop");
    @hideTimerButton = menu.AddButton("Hide timer");
    @backButton = menu.AddButton("Back to race");
    menu.AddSpace(0);
    @closeButton = menu.AddButton("Close");
    menu.visible = false;
    hideTimerButton.visible = false;

    string id = OwnId();
    idxTime = FindSetting(id, "Time limit (minutes)");
    idxSkips = FindSetting(id, "Free skips");
    idxPool = FindSetting(id, "Track pool");
    idxKey = FindSetting(id, "Skip key code");
    idxDelay = FindSetting(id, "Delay after author time (seconds)");
    idxCap = FindSetting(id, "Workshop map limit");
    idxShare = FindSetting(id, "Game track share (%)");

    // The HUD.
    @hud = UI::CreateWindow();
    hud.SetAnchor(0, 0);
    hud.SetPivot(0, 0);
    hud.SetOffset(12, 12);
    @timeText = hud.AddText("0:00", 30);
    hud.AddSpace(8);
    @scoreText = hud.AddText("Score: 0", 21);
    hud.NewRow();
    @skipsText = hud.AddText("", 13);
    hud.AddSpace(4);
    @trackText = hud.AddText("", 12);
    hud.NewRow();
    @messageText = hud.AddText("", 13);
    messageText.SetColor(0.45f, 1, 0.55f, 1);
    hud.visible = false;

    CacheOfficial();
    SyncMenu();
    Log::Info("Author Time Challenge is ready.");
}

void OnSettingsChanged()
{
    SyncMenu();
}

void OnDisabled()
{
    if (pickQuery >= 0)
        Workshop::Forget(pickQuery);
    UI::SetCursorVisible(false);
}

void Update(float dt)
{
    CacheOfficial();

    if (footerButton.Clicked())
        menuOpen = !menuOpen;
    if (menuOpen)
    {
        ReadMenu();
        if (closeButton.Clicked())
            menuOpen = false;
        if (startButton.Clicked() && !active && pendingStart == 0)
        {
            SubmitAll();                    // Typed values are committed first, then the challenge starts.
            pendingStart = 3;
        }
        if (stopButton.Clicked() && active)
            EndChallenge(false);
        if (backButton.Clicked())
            BackToRace();
        if (hideTimerButton.Clicked())
        {
            resultShown = false;
            messageUntil = 0;
        }
    }
    if (pendingStart > 0 && --pendingStart == 0)
        StartChallenge();

    if (listeningKey)
    {
        if (!menuOpen)
            listeningKey = false;
        else if (keyListenDelay > 0)
            keyListenDelay--;
        else
        {
            Input::Key pressed = Input::AnyPressed();
            if (pressed == Input::Escape)
                listeningKey = false;
            else if (pressed != Input::None && pressed != Input::MouseLeft)
            {
                listeningKey = false;
                Commit(idxKey, "" + int(pressed));
            }
            SyncMenu();
        }
    }

    bool skipRequested = menuOpen && skipButton.Clicked();
    if (active && !listeningKey && Input::Pressed(SkipKey()))
        skipRequested = true;

    if (active)
        TickChallenge(dt, skipRequested);

    UpdateMenu();
    UpdateHud();
}
