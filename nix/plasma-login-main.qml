// References:
// - Plasma Login Manager 6.6 greeter: https://github.com/KDE/plasma-login-manager/blob/Plasma/6.6/src/frontend/greeter/qml/Main.qml
// - Plasma Login Manager 6.6 state: https://github.com/KDE/plasma-login-manager/blob/Plasma/6.6/src/frontend/greeter/qml/GreeterState.qml

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.plasma.login as PlasmaLogin

Item {
    id: root
    anchors.fill: parent

    property bool authenticationPending: false
    property string statusText: ""

    readonly property string username: {
        const lastUser = PlasmaLogin.StateConfig.lastLoggedInUser;
        if (lastUser !== "" && PlasmaLogin.UserModel.indexOfData(lastUser, PlasmaLogin.UserModel.NameRole) !== -1) {
            return lastUser;
        }

        const index = PlasmaLogin.GreeterState.userListIndex;
        if (index >= 0 && index < PlasmaLogin.UserModel.rowCount()) {
            return PlasmaLogin.UserModel.data(PlasmaLogin.UserModel.index(index, 0), PlasmaLogin.UserModel.NameRole);
        }

        return "";
    }

    readonly property int sessionIndex: PlasmaLogin.GreeterState.sessionIndex
    readonly property var sessionType: PlasmaLogin.SessionModel.data(
        PlasmaLogin.SessionModel.index(sessionIndex, 0),
        PlasmaLogin.SessionModel.TypeRole
    )
    readonly property string sessionFileName: PlasmaLogin.SessionModel.data(
        PlasmaLogin.SessionModel.index(sessionIndex, 0),
        PlasmaLogin.SessionModel.FileNameRole
    )

    function startLogin() {
        if (authenticationPending || username === "" || passwordInput.text === "") {
            return;
        }

        authenticationPending = true;
        statusText = "指紋センサーに触れてください";
        PlasmaLogin.GreeterState.handleLoginRequest(username, passwordInput.text, sessionType, sessionFileName);
    }

    Rectangle {
        anchors.fill: parent
        color: "#18000000"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: passwordInput.forceActiveFocus()
    }

    Column {
        id: authentication
        anchors.centerIn: parent
        width: Math.min(360, parent.width - 64)
        spacing: 16

        Behavior on opacity {
            NumberAnimation {
                duration: 240
                easing.type: Easing.OutCubic
            }
        }

        Text {
            width: parent.width
            text: root.username
            color: "#F2F2F2"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 20
            font.weight: Font.Medium
            font.letterSpacing: 0.8
            opacity: 0.94
        }

        Item {
            width: parent.width
            height: 44

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2
                text: "password"
                color: "#70FFFFFF"
                font.pixelSize: 13
                visible: passwordInput.text.length === 0
            }

            TextInput {
                id: passwordInput
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                anchors.bottomMargin: 5
                verticalAlignment: TextInput.AlignVCenter
                color: "#F4F4F4"
                selectionColor: "#55FFFFFF"
                selectedTextColor: "#FFFFFF"
                font.pixelSize: 15
                echoMode: TextInput.Password
                enabled: !root.authenticationPending
                selectByMouse: true
                focus: true

                onAccepted: root.startLogin()
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#5CFFFFFF"
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: passwordInput.activeFocus ? parent.width : 0
                height: 2
                color: "#E8FFFFFF"

                Behavior on width {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 24

            Text {
                id: status
                anchors.centerIn: parent
                width: parent.width
                text: root.statusText
                color: "#D9FFFFFF"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: 12
                font.letterSpacing: 0.25
                visible: text.length > 0
                opacity: visible ? 0.7 : 0

                SequentialAnimation on opacity {
                    running: status.visible && root.authenticationPending
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 0.48
                        to: 0.82
                        duration: 1100
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: 0.82
                        to: 0.48
                        duration: 1100
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }

    RowLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 26
        anchors.bottomMargin: 22
        spacing: 4

        QQC2.Button {
            id: sleepButton
            text: "sleep"
            visible: PlasmaLogin.SessionManagement.canSuspend
            flat: true
            onClicked: {
                PlasmaLogin.GreeterState.clearPasswords();
                PlasmaLogin.SessionManagement.suspend();
            }

            background: Rectangle {
                radius: 8
                color: sleepButton.hovered || sleepButton.activeFocus ? "#18FFFFFF" : "transparent"
            }

            contentItem: Text {
                text: sleepButton.text
                color: "#AFFFFFFF"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 11
                font.letterSpacing: 0.9
            }
        }

        QQC2.Button {
            id: restartButton
            text: "restart"
            visible: PlasmaLogin.SessionManagement.canReboot
            flat: true
            onClicked: PlasmaLogin.SessionManagement.requestReboot(PlasmaLogin.SessionManagement.ConfirmationMode.Skip)

            background: Rectangle {
                radius: 8
                color: restartButton.hovered || restartButton.activeFocus ? "#18FFFFFF" : "transparent"
            }

            contentItem: Text {
                text: restartButton.text
                color: "#AFFFFFFF"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 11
                font.letterSpacing: 0.9
            }
        }

        QQC2.Button {
            id: powerButton
            text: "power"
            visible: PlasmaLogin.SessionManagement.canShutdown
            flat: true
            onClicked: PlasmaLogin.SessionManagement.requestShutdown(PlasmaLogin.SessionManagement.ConfirmationMode.Skip)

            background: Rectangle {
                radius: 8
                color: powerButton.hovered || powerButton.activeFocus ? "#18FFFFFF" : "transparent"
            }

            contentItem: Text {
                text: powerButton.text
                color: "#AFFFFFFF"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 11
                font.letterSpacing: 0.9
            }
        }
    }

    Connections {
        target: PlasmaLogin.Authenticator

        function onInformationMessage(message) {
            if (message !== "") {
                root.statusText = message;
            }
        }

        function onLoginFailed() {
            root.authenticationPending = false;
            root.statusText = "認証できませんでした";
            passwordInput.selectAll();
            passwordInput.forceActiveFocus();
        }

        function onLoginSucceeded() {
            root.statusText = "";
            authentication.opacity = 0;
        }
    }

    Component.onCompleted: Qt.callLater(() => passwordInput.forceActiveFocus())
}
