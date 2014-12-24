import QtQuick 2.0
import Ubuntu.Components 1.1
import Ubuntu.PushNotifications 0.1
import Ubuntu.Components.ListItems 1.0 as ListItem
import U1db 1.0 as U1db


/*!
    \brief MainView with a Label and Button elements.
*/

MainView {
    id: mainView
    // objectName for functional testing purposes (autopilot-qt5)
    objectName: "mainView"

    // Note! applicationName needs to match the "name" field of the click manifest
    applicationName: "org.kryogenix.caxton"

    /*
     This property enables the application to change orientation
     when the device is rotated. The default is false.
    */
    //automaticOrientation: true

    // Removes the old toolbar and enables new features of the new header.
    useDeprecatedToolbar: false

    width: units.gu(100)
    height: units.gu(75)

    backgroundColor: "#1b3540"

    Timer {
        id: unsetCodeAfterTokenRetrieved
        interval: 1500; running: false; repeat: false
        onTriggered: code.text = ""
    }

    PushClient {
        id: pushClient
        Component.onCompleted: {
            notificationsChanged.connect(function(msgs) {
                console.log("GOT MESSAGES", JSON.stringify(msgs));
                for (var k in msgs) {
                    var m = JSON.parse(msgs[k]);
                    if (m.url && m.type == "user") {
                        db.putDoc({
                            data: {
                                type: "url",
                                url: m.url,
                                message: m.message,
                                appname: m.appname,
                                date: (new Date()).getTime()
                            }
                        });
                        console.log("added to db");
                        mainView.reaggregateListModels();
                    } else if (m.type == "token-received") {
                        if (m.code == code.text) {
                            code.text = "Paired OK!";
                            b.state = "waiting";
                            unsetCodeAfterTokenRetrieved.start();
                        }
                    }
                }
            });
            error.connect(function(err) {
                console.log("GOT ERROR", err);
            });
            getNotifications();
        }
        appId: "org.kryogenix.caxton_caxton"
    }

    U1db.Database { id: db; path: "caxton.u1db" }
    U1db.Index {
        database: db
        id: by_type
        /* You have to specify in the index all fields you want to retrieve
           The query should return the whole document, not just indexed fields
           https://bugs.launchpad.net/u1db-qt/+bug/1271973 */
        expression: ["data.type", "data.date", "data.url", "data.appname", "data.message"]
    }
    U1db.Query {
        id: urls
        index: by_type
        query: ["url", "*", "*", "*", "*"]
        Component.onCompleted: sorted_urls.sortme()
    }
    U1db.Index {
        database: db
        id: by_appname
        /* You have to specify in the index all fields you want to retrieve
           The query should return the whole document, not just indexed fields
           https://bugs.launchpad.net/u1db-qt/+bug/1271973 */
        expression: ["data.type", "data.appname"]
    }
    U1db.Query {
        id: appnames
        index: by_appname
        query: ["url", "*"]
        Component.onCompleted: grouped_appnames.group();
    }
    U1db.Index {
        database: db
        id: by_app_block
        /* You have to specify in the index all fields you want to retrieve
           The query should return the whole document, not just indexed fields
           https://bugs.launchpad.net/u1db-qt/+bug/1271973 */
        expression: ["data.type", "data.appname"]
    }
    U1db.Query {
        id: blocked_apps
        index: by_app_block
        query: ["block", "*"]
        Component.onCompleted: grouped_appnames.group();
    }

    function reaggregateListModels() {
        sorted_urls.sortme();
        grouped_appnames.group();
    }

    /* Bodge-o-rama, but u1db doesn't support sorted results */
    ListModel {
        id: sorted_urls
        function sortme() {
            var lst = [];
            var blocked = {};
            blocked_apps.results.forEach(function(bl) { blocked[bl.appname] = "yes"; });
            for (var i=0; i<urls.results.length; i++) {
                if (blocked[urls.results[i].appname]) continue;
                lst.push({docId: urls.documents[i], contents: urls.results[i]});
            };
            lst.sort(function(a,b) { return b.contents.date - a.contents.date; });
            sorted_urls.clear();
            lst.forEach(function(li) { sorted_urls.append(li); });
        }
    }

    ListModel {
        id: grouped_appnames
        function group() {
            var counts = {};
            appnames.results.forEach(function(an) {
               if (counts[an.appname]) {
                   counts[an.appname].count += 1;
               } else {
                   counts[an.appname] = {count: 1, blocked: false};
               }
            });
            for (var i=0; i<blocked_apps.results.length; i++) {
                if (counts[blocked_apps.results[i].appname]) {
                    counts[blocked_apps.results[i].appname].blocked = true;
                    counts[blocked_apps.results[i].appname].docId = blocked_apps.documents[i];
                }
            }
            grouped_appnames.clear();
            for (var an in counts) {
                grouped_appnames.append({appname: an, count: counts[an].count,
                                         blocked: counts[an].blocked, docId: counts[an].docId});
            }
        }
    }

    Tabs {
        Tab {
            title: i18n.tr("Caxton")
            page:     Page {
                id: pg

                Column {
                    id: col
                    width: parent.width
                    spacing: units.gu(1)
                    Item {
                        id: spacer /* sigh */
                        height: 1
                        width: parent.width
                    }

                    Button {
                        id: b
                        state: "waiting"
                        text: "Get a code for an app"
                        width: parent.width - units.gu(4)
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: units.gu(3)
                        gradient: UbuntuColors.orangeGradient
                        onClicked: {
                            b.state = "getting";
                            var x = new XMLHttpRequest();
                            x.open("POST", "http://caxton.herokuapp.com/api/getcode", true);
                            x.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
                            x.onreadystatechange = function() {
                                if (x.readyState == 4) {
                                    b.state = "gotcode";
                                    console.log(x.status);
                                    console.log(x.responseText);
                                    console.log(new Date());
                                    try {
                                        var j = JSON.parse(x.responseText);
                                        if (!j.code) throw new Error();
                                        code.text = j.code;
                                    } catch(e) {
                                        code.text = "Server error";
                                    }

                                }
                            }
                            x.send("pushtoken=" + encodeURIComponent(pushClient.token) + "&appversion=0.1");
                        }
                        states: [
                            State {
                                name: "waiting"
                                PropertyChanges { target: b; text: "Get a code for an app" }
                                PropertyChanges { target: b; enabled: true }
                            },
                            State {
                                name: "getting"
                                PropertyChanges { target: b; text: "Getting a code" }
                                PropertyChanges { target: code; text: "..." }
                                PropertyChanges { target: b; enabled: false }
                            },
                            State {
                                name: "gotcode"
                                PropertyChanges { target: b; text: "Get a code for an app" }
                                PropertyChanges { target: b; enabled: true }
                            }
                        ]
                    }
                    ActivityIndicator {
                        id: spinner
                        height: code.height
                        anchors.horizontalCenter: parent.horizontalCenter
                        running: b.state == "getting"
                        visible: running
                    }

                    Label {
                        id: code
                        text: ""
                        horizontalAlignment: Text.AlignHCenter
                        fontSize: "x-large"
                        width: parent.width
                        visible: !spinner.running
                    }
                    ListView {

                        Scrollbar {
                            flickableItem: urllist
                            align: Qt.AlignTrailing
                        }

                        id: urllist
                        model: sorted_urls
                        width: parent.width
                        height: pg.height - b.height - code.height - spacer.height - (col.spacing * 3)
                        delegate: ListItem.Empty{ /* make my own listitem */

                            __height: Math.max(contItem.height, units.gu(6))
                            id: subtitledListItem
                            removable: true
                            onItemRemoved: {
                                db.putDoc("", model.docId);
                                mainView.reaggregateListModels();
                            }
                            onClicked: {
                                console.log(model.contents.url);
                                Qt.openUrlExternally(model.contents.url);
                            }
                            Item {
                                id: contItem
                                anchors.leftMargin: units.gu(2)
                                anchors.rightMargin: units.gu(2)

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: childrenRect.height + label.anchors.topMargin + subLabel.anchors.bottomMargin
                                Label {
                                    id: label
                                    text: model.contents.message || model.contents.url
                                    elide: Text.ElideMiddle
                                    anchors {
                                        top: parent.top
                                        left: parent.left
                                        right: parent.right
                                    }
                                }
                                Label {
                                    id: subLabel
                                    text: model.contents.appname
                                    width: (parent.width / 2) - units.gu(1)
                                    anchors {
                                        left: parent.left
                                        top: label.bottom
                                    }
                                    fontSize: "x-small"
                                    maximumLineCount: 1
                                    clip: true
                                    color: Theme.palette.normal.backgroundText
                                }
                                Label {
                                    id: dateLabel
                                    text: {
                                        var dt = new Date(model.contents.date);
                                        return dt.getHours() + "." + dt.getMinutes() + " " + dt.getDate() + "/" + dt.getMonth() + "/" + dt.getFullYear();
                                    }
                                    width: (parent.width / 2) - units.gu(1)
                                    horizontalAlignment: Text.AlignRight
                                    anchors {
                                        right: parent.right
                                        top: label.bottom
                                    }
                                    fontSize: "x-small"
                                    maximumLineCount: 1
                                    clip: true
                                    color: Theme.palette.normal.backgroundText
                                }
                            }
                        }
                    }
                }
            }
        }
        Tab {
            title: i18n.tr("Apps")
            page: Page {
                id: appnamepage
                property bool editing: false
                ListView {
                    model: grouped_appnames
                    clip: true
                    anchors.fill: parent
                    delegate: ListItem.Empty{ /* make my own listitem */
                        __height: Math.max(app_contItem.height, units.gu(6))
                        id: app_subtitledListItem
                        removable: false
                        highlightWhenPressed: appnamepage.editing
                        onClicked: {
                            if (appnamepage.editing) {
                                if (model.blocked) {
                                    console.log("deleting", model.docId);
                                    db.putDoc("", model.docId);
                                } else {
                                    db.putDoc({data: {type: "block", appname: model.appname}})
                                }
                                mainView.reaggregateListModels();
                            }
                        }
                        Item {
                            id: app_contItem
                            anchors.leftMargin: units.gu(2)
                            anchors.rightMargin: units.gu(2)

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: childrenRect.height + app_label.anchors.topMargin + app_subLabel.anchors.bottomMargin

                            Image {
                                source: model.blocked ? "blocked.svg" : "block.svg"
                                id: icon
                                width: appnamepage.editing ? parent.height - units.gu(1) : 0
                                height: parent.height - units.gu(1)
                                fillMode: Image.PreserveAspectFit
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                visible: appnamepage.editing
                            }

                            Label {
                                id: app_label
                                text: model.appname
                                width: parent.width - icon.width - units.gu(1)
                                anchors {
                                    top: parent.top
                                    left: icon.right
                                    right: parent.right
                                    leftMargin: appnamepage.editing ? units.gu(1): 0
                                }
                                maximumLineCount: 1
                                clip: true
                                font.strikeout: model.blocked
                            }
                            Label {
                                id: app_subLabel
                                text: model.count + " notification" + (model.count == 1 ? "" : "s")
                                width: parent.width - icon.width - units.gu(1)
                                anchors {
                                    left: icon.right
                                    top: app_label.bottom
                                    leftMargin: appnamepage.editing ? units.gu(1): 0
                                }
                                fontSize: "x-small"
                                maximumLineCount: 1
                                clip: true
                                color: Theme.palette.normal.backgroundText
                            }
                        }
                    }
                }
                head.actions: [
                    Action {
                        iconName: appnamepage.editing ? "clear-search": "edit"
                        onTriggered: appnamepage.editing = !appnamepage.editing
                        text: appnamepage.editing ? i18n.tr("Done"): i18n.tr("Edit")
                    }
                ]
            }
        }
    }
}

