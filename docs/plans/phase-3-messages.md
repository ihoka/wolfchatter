# Phase 3 — Messages & Real Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** People can set a display name once and post messages in a room. New messages and new pins
appear live for everyone watching.

**Architecture:**
- **Display name.** The name lives in a signed, permanent cookie behind a small `DisplayName` value
  object, so it is validated once when set.
- **Posting.** The message author is always taken from that cookie, never from params. Posting
  responds with a Turbo Stream that appends the message and resets the form.
- **Live updates.** Models broadcast synchronously on commit (`broadcast_append_to`) to two streams:
  each room's stream for messages, and a global `chatrooms` stream for marker elements.
- **De-duplication.** Turbo de-duplicates appends by element id, so the sender's own response and the
  broadcast never double up. Rooms already de-duplicate pins by room id.

**Tech Stack:** Rails 8.1.4, Turbo Streams over Action Cable (Solid Cable), Stimulus, Minitest + Capybara.

**Spec:** [`docs/superpowers/specs/2026-11-09-wolfchatter-design.md`](../superpowers/specs/2026-11-09-wolfchatter-design.md) ·
PRD: [`docs/prd.md`](../prd.md) (FR-5, FR-6, FR-7, FR-8; data model; real-time design) ·
Carry-forward: [`00-overview.md`](00-overview.md#carry-forward-notes-for-later-phase-plans) (phase 3 items)

## Global Constraints

- **PRD `messages` table, verbatim:**
  - `chatroom_id` bigint not null, foreign key;
  - `author_name` string not null, stripped, max 40;
  - `body` text not null, present, max 1000 characters;
  - index `messages(chatroom_id, created_at)`;
  - ordering by `created_at`, then `id`.
- **Display name rule:** stripped, required, max 40 characters, always rendered escaped. The panel
  shows "Chatting as <name>" with a "change" control.
- **Mockup copy:** the name field placeholder is "write your user name here". The message field
  placeholder is "write message here". The button reads "Submit".
- **Turbo de-duplication:** every message element has id `dom_id(message)`.
- **Bounded history:** the panel shows the 100 most recent messages, oldest first. Older messages
  exist but are not shown. This is a documented limit.
- **Timestamps:** shown as `%d/%m/%Y %H:%M` UTC with a `<time datetime>` element. UTC is a
  documented limit.
- **Broadcasts are synchronous** (`broadcast_append_to`, inside `after_create_commit`), not
  `_later`. They are cheap inserts into Solid Cable, they need no job process, and system tests see
  them under the `:test` job adapter. This settles the phase 3 carry-forward note.
- **Constraints carried over from earlier phases:**
  - Hotwire only, and pins only as marker elements.
  - Prosopite stays on, and every test is green.
  - `bin/rubocop` and `bin/brakeman` are clean.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branch `phase-3-messages`.

## Review Focus

- **Author spoofing via params.** A forged `message[author_name]` param is ignored. The author always
  comes from the cookie (integration test in Task 3).
- **Posting with no name.** Posting without a name cookie returns 422 and saves nothing. This covers a
  cookie that was cleared or expired (Task 3).
- **HTML or script in names and bodies.** Both render as literal text, in the response and in the
  broadcast (Task 3 integration test plus Task 4 system test).
- **Whitespace-only input.** A blank body or a whitespace-only name is rejected after stripping
  (Tasks 1 and 2).
- **Live updates reaching another viewer.** A second browser session sees a new message and a new pin
  without reloading (Task 4).

---

### Task 1: Message model and N+1 proof

**Files:**
- Create: `db/migrate/<ts>_create_messages.rb`, `app/models/message.rb`, `test/models/message_test.rb`,
  `test/fixtures/messages.yml`, `test/models/prosopite_test.rb`
- Modify: `app/models/chatroom.rb` (add `has_many :messages, dependent: :destroy`)

**Interfaces:**
- Produces:
  - `Message` (`belongs_to :chatroom`)
  - `Message::MAX_BODY_LENGTH = 1000`
  - `Message.chronological` → `order(:created_at, :id)`
  - `Chatroom#recent_messages(limit = 100)` → an Array of the newest `limit` messages, oldest first
  - fixtures `messages(:hello)` and `messages(:reply)`, both in `chatrooms(:cluj)`, with distinct `created_at`

- [ ] **Step 1: Write failing tests**

```ruby
# test/models/message_test.rb
require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "strips author and body" do
    message = chatrooms(:cluj).messages.create!(author_name: "  Ana  ", body: "  hi  ")
    assert_equal "Ana", message.author_name
    assert_equal "hi", message.body
  end

  test "rejects blank or whitespace-only body" do
    assert_not chatrooms(:cluj).messages.build(author_name: "Ana", body: "   ").valid?
  end

  test "rejects body over 1000 characters" do
    assert chatrooms(:cluj).messages.build(author_name: "Ana", body: "a" * 1000).valid?
    assert_not chatrooms(:cluj).messages.build(author_name: "Ana", body: "a" * 1001).valid?
  end

  test "rejects missing or over-long author" do
    assert_not chatrooms(:cluj).messages.build(author_name: " ", body: "hi").valid?
    assert_not chatrooms(:cluj).messages.build(author_name: "a" * 41, body: "hi").valid?
  end

  test "recent_messages returns the newest N oldest-first" do
    room = chatrooms(:rome)
    3.times { |i| room.messages.create!(author_name: "A", body: "m#{i}", created_at: i.minutes.from_now) }
    assert_equal %w[m1 m2], room.recent_messages(2).map(&:body)
  end
end

# test/models/prosopite_test.rb
require "test_helper"

class ProsopiteTest < ActiveSupport::TestCase
  test "an N+1 query raises in the test environment" do
    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.scan { Chatroom.all.each { |room| room.messages.to_a } }
    end
  end
end
```

- [ ] **Step 2:** `bin/rails test test/models` → FAIL.
- [ ] **Step 3:** Implement:
  - The migration follows the PRD: `t.references :chatroom, null: false, foreign_key: true, index: false`
    plus `add_index :messages, %i[chatroom_id created_at]`.
  - Use `normalizes :author_name, :body, with: ->(value) { value.strip }`.
  - Validate presence and length. Take the author max from `DisplayName::MAX_LENGTH` if Task 2 has
    already landed; otherwise use 40 here and point it at the constant in Task 2.
  - `recent_messages`: `messages.order(created_at: :desc, id: :desc).limit(limit).reverse`.
  - Note: `test/models/prosopite_test.rb` runs inside the `setup { Prosopite.scan }` from
    `test_helper`. A nested `scan` is a no-op, so if the block form does not raise, call
    `Prosopite.finish` first inside the test, then scan. Report which variant works.
- [ ] **Step 4:** `bin/rails db:migrate && bin/rails test` → PASS. `bin/rubocop` clean.
- [ ] **Step 5: Commit:** `feat: add Message model and prove Prosopite catches N+1`

### Task 2: Display name in a cookie

**Files:**
- Create:
  - `app/models/display_name.rb` (ActiveModel)
  - `app/controllers/concerns/display_name_cookie.rb`
  - `app/controllers/display_names_controller.rb`
  - `app/views/chatrooms/_compose.html.erb`
  - `app/views/display_names/_form.html.erb`
- Modify: `app/controllers/application_controller.rb`, `config/routes.rb`, `app/views/chatrooms/_panel.html.erb`
- Test: `test/models/display_name_test.rb`, `test/controllers/display_names_controller_test.rb`

**Interfaces:**
- Produces:
  - **`DisplayName`**
    - `DisplayName.new(name:)` with `#name`, stripped.
    - Validations: presence, length ≤ `DisplayName::MAX_LENGTH = 40`.
  - **`DisplayNameCookie` concern**, included in `ApplicationController`:
    - `current_display_name` → String or nil. It reads `cookies.signed[:display_name]`, and is also
      exposed as a `helper_method`.
    - `remember_display_name(name)` sets `cookies.permanent.signed[:display_name]`, `httponly: true`,
      `same_site: :lax`.
    - `forget_display_name` deletes the cookie.
  - **Route:** `resource :display_name, only: %i[update destroy]`. Params are
    `display_name[name]` and `chatroom_id`.
  - **Responses.** Both actions respond with
    `turbo_stream.replace(dom_id(chatroom, :compose), partial: "chatrooms/compose", locals: { chatroom: })`.
    An invalid name gets 422 and re-renders the form with its errors.
  - **`_compose`** (local `chatroom`), wrapped in `<div id="<%= dom_id(chatroom, :compose) %>">`:
    - With a name: "Chatting as <strong>NAME</strong>", a "change" `button_to` (DELETE
      display_name with `chatroom_id`), and a placeholder slot where Task 3 renders the message form.
    - Without a name: `display_names/_form` (a text field with placeholder "write your user name here",
      submit "Save name").
  - **`_panel`** renders `_compose` under the title.

- [ ] **Step 1: Write failing tests**

```ruby
# test/models/display_name_test.rb
require "test_helper"

class DisplayNameTest < ActiveSupport::TestCase
  test "strips and accepts up to 40 characters" do
    assert_equal "Ana", DisplayName.new(name: "  Ana ").name
    assert DisplayName.new(name: "a" * 40).valid?
    assert_not DisplayName.new(name: "a" * 41).valid?
    assert_not DisplayName.new(name: "   ").valid?
  end
end

# test/controllers/display_names_controller_test.rb
require "test_helper"

class DisplayNamesControllerTest < ActionDispatch::IntegrationTest
  test "setting a name stores it and swaps in the compose area" do
    patch display_name_path, params: { display_name: { name: " Ana " }, chatroom_id: chatrooms(:cluj).id },
                             as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", dom_id(chatrooms(:cluj), :compose)
    assert_includes response.body, "Chatting as"
    get chatroom_path(chatrooms(:cluj))
    assert_select "##{dom_id(chatrooms(:cluj), :compose)}", text: /Chatting as\s+Ana/
  end

  test "an invalid name is rejected" do
    patch display_name_path, params: { display_name: { name: "a" * 41 }, chatroom_id: chatrooms(:cluj).id },
                             as: :turbo_stream
    assert_response :unprocessable_content
  end

  test "changing the name forgets it" do
    patch display_name_path, params: { display_name: { name: "Ana" }, chatroom_id: chatrooms(:cluj).id }, as: :turbo_stream
    delete display_name_path, params: { chatroom_id: chatrooms(:cluj).id }, as: :turbo_stream
    get chatroom_path(chatrooms(:cluj))
    assert_select "input[placeholder='write your user name here']"
  end

  test "a name with markup is rendered escaped" do
    patch display_name_path, params: { display_name: { name: "<b>x</b>" }, chatroom_id: chatrooms(:cluj).id }, as: :turbo_stream
    get chatroom_path(chatrooms(:cluj))
    assert_select "##{dom_id(chatrooms(:cluj), :compose)} b", count: 0
    assert_includes response.body, "&lt;b&gt;x&lt;/b&gt;"
  end
end
```

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement per Interfaces. Look up the chatroom with `Chatroom.find(params.expect(:chatroom_id))`.
- [ ] **Step 4:** Full suite, rubocop and brakeman → green.
- [ ] **Step 5: Commit:** `feat: remember the display name in a signed cookie`

### Task 3: Posting and showing messages

**Files:**
- Create:
  - `app/controllers/messages_controller.rb`
  - `app/views/messages/_message.html.erb`
  - `app/views/messages/_form.html.erb`
  - `app/javascript/controllers/scroll_controller.js`
- Modify: `config/routes.rb`, `app/views/chatrooms/_panel.html.erb`, `app/views/chatrooms/_compose.html.erb`
- Test: `test/controllers/messages_controller_test.rb`, `test/system/messages_test.rb`

**Interfaces:**
- Consumes: `current_display_name` and `_compose` (Task 2); `Chatroom#recent_messages` and `Message` (Task 1).
- Produces:
  - **Route:** `resources :chatrooms, only: %i[index show create] do resources :messages, only: :create end`.
  - **`MessagesController#create`**
    - Params are `message[body]` only. `author_name = current_display_name`.
    - Without a name, it responds 422 and saves nothing.
    - On success it responds with a turbo_stream that appends `messages/_message` to
      `dom_id(chatroom, :messages)` and replaces `dom_id(chatroom, :message_form)` with a fresh form.
    - When invalid, it responds 422 and replaces the form with errors shown.
  - **`messages/_message`**
    - `<article id="<%= dom_id(message) %>">` containing the author (bold), the body (`simple_format`
      is not allowed; keep plain text with `whitespace-pre-line`), and
      `<time datetime=ISO8601>` with text `%d/%m/%Y %H:%M UTC`.
  - **`messages/_form`** (local `chatroom`, optional `message`)
    - id `dom_id(chatroom, :message_form)`.
    - A text field `message[body]` with placeholder "write message here", `maxlength: 1000`,
      `required`, and `autocomplete: off`.
    - A submit button labelled "Submit".
  - **Panel message list:** `<div id="<%= dom_id(chatroom, :messages) %>" role="log" aria-live="polite"
    data-controller="scroll" class="max-h-[50vh] overflow-y-auto">` rendering `chatroom.recent_messages`.
  - **`scroll` controller:** scrolls to the bottom on connect, and again whenever a child is added
    (via a MutationObserver that is disconnected on disconnect).

- [ ] **Step 1: Write failing tests**

```ruby
# test/controllers/messages_controller_test.rb
require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @room = chatrooms(:cluj)
    patch display_name_path, params: { display_name: { name: "Ana" }, chatroom_id: @room.id }, as: :turbo_stream
  end

  test "posting appends the message as the cookie's author" do
    assert_difference -> { @room.messages.count }, 1 do
      post chatroom_messages_path(@room), params: { message: { body: "Hello", author_name: "Mallory" } },
                                          as: :turbo_stream
    end
    assert_response :success
    assert_equal "Ana", @room.messages.last.author_name
    assert_select "turbo-stream[action=append][target=?]", dom_id(@room, :messages)
  end

  test "blank body is rejected" do
    assert_no_difference -> { Message.count } do
      post chatroom_messages_path(@room), params: { message: { body: "  " } }, as: :turbo_stream
    end
    assert_response :unprocessable_content
  end

  test "posting without a name is rejected" do
    delete display_name_path, params: { chatroom_id: @room.id }, as: :turbo_stream
    assert_no_difference -> { Message.count } do
      post chatroom_messages_path(@room), params: { message: { body: "hi" } }, as: :turbo_stream
    end
    assert_response :unprocessable_content
  end

  test "message markup is escaped" do
    post chatroom_messages_path(@room), params: { message: { body: "<script>x</script>" } }, as: :turbo_stream
    assert_not_includes response.body, "<script>x</script>"
  end

  test "room page lists recent messages oldest first" do
    get chatroom_path(@room)
    bodies = css_select("##{dom_id(@room, :messages)} article").map { _1.at_css("p")&.text.to_s.strip }
    assert_equal [messages(:hello).body, messages(:reply).body], bodies
  end
end

# test/system/messages_test.rb
require "application_system_test_case"

class MessagesTest < ApplicationSystemTestCase
  test "set a name once, then post messages" do
    visit chatroom_path(chatrooms(:rome))
    fill_in placeholder: "write your user name here", with: "Ana"
    click_on "Save name"
    assert_text "Chatting as Ana"
    fill_in placeholder: "write message here", with: "Ciao!"
    click_on "Submit"
    within("##{dom_id(chatrooms(:rome), :messages)}") { assert_text "Ciao!" }
    assert_field placeholder: "write message here", with: ""
    visit chatroom_path(chatrooms(:cluj))
    assert_text "Chatting as Ana"
  end
end
```

The room-page test's body selector assumes the body is in a `<p>`. If you choose different markup,
adjust that selector and keep the assertion.

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement per Interfaces.
- [ ] **Step 4:** Full suite, rubocop and brakeman → green. Run `test/system/messages_test.rb` 3 times.
- [ ] **Step 5: Commit:** `feat: post and show messages in the chat panel`

### Task 4: Live messages and live pins

**Files:**
- Modify:
  - `app/models/message.rb`
  - `app/models/chatroom.rb`
  - `app/views/chatrooms/_panel.html.erb` (`turbo_stream_from chatroom`)
  - `app/views/chatrooms/_map_page.html.erb` (`turbo_stream_from "chatrooms"` inside `#map_container`)
- Test: `test/models/message_test.rb`, `test/models/chatroom_test.rb`, `test/system/live_updates_test.rb`

**Interfaces:**
- Produces:
  - `Message`: `after_create_commit { broadcast_append_to chatroom, target: ActionView::RecordIdentifier.dom_id(chatroom, :messages), partial: "messages/message", locals: { message: self } }`.
  - `Chatroom`: `after_create_commit { broadcast_append_to "chatrooms", target: "markers", partial: "chatrooms/marker", locals: { chatroom: self } }`.

- [ ] **Step 1: Write failing tests**

```ruby
# in MessageTest (include Turbo::Broadcastable::TestHelper)
test "creating a message broadcasts it to the room" do
  room = chatrooms(:cluj)
  assert_turbo_stream_broadcasts(room, count: 1) do
    room.messages.create!(author_name: "Ana", body: "hi")
  end
end

# in ChatroomTest (include Turbo::Broadcastable::TestHelper)
test "creating a room broadcasts its marker" do
  assert_turbo_stream_broadcasts("chatrooms", count: 1) do
    Chatroom.create!(latitude: 1, longitude: 2)
  end
end

# test/system/live_updates_test.rb
require "application_system_test_case"

class LiveUpdatesTest < ApplicationSystemTestCase
  test "another viewer sees new messages and pins live" do
    room = chatrooms(:rome)
    using_session(:watcher) do
      visit chatroom_path(room)
      assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
    end

    visit chatroom_path(room)
    fill_in placeholder: "write your user name here", with: "Ana"
    click_on "Save name"
    fill_in placeholder: "write message here", with: "<b>live</b>"
    click_on "Submit"
    find("#map").click(x: -300, y: 200)
    assert_selector ".leaflet-marker-icon", count: Chatroom.count

    using_session(:watcher) do
      within("##{dom_id(room, :messages)}") do
        assert_text "<b>live</b>"
        assert_no_selector "b", text: "live"
      end
      assert_selector ".leaflet-marker-icon", count: Chatroom.count
    end
  end
end
```

Also add this test. Back/forward must not show a stale cached panel. Room pages send
`<meta name="turbo-cache-control" content="no-cache">` through `content_for :head`, so a
restoration visit re-fetches:

```ruby
test "going back to a room shows messages that arrived while away" do
  cluj, rome = chatrooms(:cluj), chatrooms(:rome)
  visit chatroom_path(cluj)
  find(".leaflet-marker-icon[title='Rome, Italy']").click
  assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
  cluj.messages.create!(author_name: "Bo", body: "while you were away")
  page.go_back
  within("##{dom_id(cluj, :messages)}") { assert_text "while you were away" }
end
```

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement per Interfaces. `turbo_stream_from` renders
  `<turbo-cable-stream-source>`, which carries the `connected` attribute once it is subscribed.
- [ ] **Step 4:** Full suite, rubocop and brakeman → green. Run `live_updates_test.rb` 3 times.
  Check the sender sees exactly one copy of their message (Turbo de-duplicates appends by id), with
  `assert_selector "##{dom_id(Message.last)}", count: 1`.
- [ ] **Step 5: Commit:** `feat: broadcast new messages and pins live`

### Task 5: Docs and PR

- [ ] **Step 1: README.md updates**
  - "Using Wolfchatter": set your name once, post messages, see others live.
  - "Improvements over the mockups": name entered once, remembered in a cookie.
  - New "Known limitations" section: honor-system names, the newest 100 messages shown, UTC
    timestamps, stray clicks create rooms, and pins created while the live connection was lost
    appear only after a full reload (`#markers` is permanent).
- [ ] **Step 2: CLAUDE.md:** the broadcasts line now says synchronous `broadcast_*_to` in
  `after_create_commit` is the project default, and why.
- [ ] **Step 3: Commit:** `docs: document messaging, live updates and limitations`
- [ ] **Step 4:** Push `phase-3-messages` and open the PR with `gh`, linking this plan.
