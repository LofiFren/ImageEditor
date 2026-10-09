// Omarchy's SDDM theme (omarchy-settings 4.0.4, Main.qml) plus a user picker.
//
// Omarchy's theme is single-user: it only has a password box and always logs
// in SDDM's last user, so a second account can never sign in. This copy says
// whose password is being asked for ("log in as < alex >") and lets the arrow
// keys or Tab choose another account, with a hint line saying so. With one
// account it looks exactly like Omarchy's. Installed as the "omarchy-uconsole"
// theme by install-theme.sh.

import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  property int userIndex: 0
  property string currentUser: users.count > 0 && users.itemAt(userIndex) ? users.itemAt(userIndex).userName : userModel.lastUser
  property bool loginFailed: false
  property bool loggingIn: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  // One invisible item per account, so names can be read by index.
  Repeater {
    id: users
    model: userModel
    delegate: Item {
      property string userName: model.name
    }
    // The list can fill in after startup: keep the last user selected.
    onItemAdded: function(index, item) {
      if (item.userName === userModel.lastUser)
        root.userIndex = index
    }
  }

  function selectLastUser() {
    for (var i = 0; i < users.count; i++) {
      if (users.itemAt(i) && users.itemAt(i).userName === userModel.lastUser) {
        root.userIndex = i
        return
      }
    }
    root.userIndex = 0
  }

  function cycleUser(step) {
    if (users.count < 2 || root.loggingIn)
      return
    root.userIndex = (root.userIndex + step + users.count) % users.count
    root.loginFailed = false
    password.text = ""
    password.forceActiveFocus()
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loggingIn = false
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 40

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    // Whose password this is. Only shown when there is a choice to make.
    Text {
      id: userLabel
      visible: users.count > 1
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.StyledText
      text: "<font color='#7f88b5'>log in as</font>  ‹ <b>" + root.currentUser + "</b> ›"
      color: "#c0caf5"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 26

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) { root.cycleUser(mouse.x < parent.width / 2 ? -1 : 1) }
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "•"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true

          onTextChanged: root.loginFailed = false

          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (!root.loggingIn) {
                root.loggingIn = true
                sddm.login(root.currentUser, password.text, root.sessionIndex)
              }
              event.accepted = true
            } else if (root.loggingIn) {
              event.accepted = true    // no switching user mid-login
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
              root.cycleUser(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
              root.cycleUser(1)
              event.accepted = true
            }
          }
        }
      }
    }

    // How to use the picker, for anyone who has not seen it before.
    Text {
      visible: users.count > 1 && !root.loggingIn
      anchors.horizontalCenter: parent.horizontalCenter
      text: "← →  switch user  ·  Enter  log in"
      color: "#7f88b5"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 20
    }

    // After Enter. Starting the session takes several seconds on a CM4, and
    // without this the screen looks frozen.
    Column {
      visible: root.loggingIn
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 12

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "logging in"
        color: "#7aa2f7"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 20
      }

      Rectangle {
        id: track
        width: 240
        height: 3
        color: "#24283b"
        anchors.horizontalCenter: parent.horizontalCenter

        Rectangle {
          id: sweep
          width: 60
          height: parent.height
          color: "#7aa2f7"

          SequentialAnimation on x {
            running: root.loggingIn
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: track.width - sweep.width; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { from: track.width - sweep.width; to: 0; duration: 700; easing.type: Easing.InOutQuad }
          }
        }
      }
    }

  }

  Component.onCompleted: {
    root.selectLastUser()
    password.forceActiveFocus()
  }
}
