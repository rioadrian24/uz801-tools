function esc(s) {
    return String(s == null ? '' : s)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function loadInbox() {
    $.getJSON('inbox.json?_=' + Date.now(), function (data) {
        var rows = '';
        var list = data.sms || [];
        for (var i = 0; i < list.length; i++) {
            var m = list[i];
            rows += '<tr class="' + (String(m.read) === '0' ? 'unread' : '') + '">'
                + '<td>' + esc(m.id) + '<br><small>HP</small></td>'
                + '<td>' + esc(m.from) + '</td>'
                + '<td>' + esc(m.date) + '</td>'
                + '<td class="msg">' + esc(m.text) + '</td>'
                + '<td><span class="del" onclick="delMsg(\'db\',' + parseInt(m.id, 10) + ')">delete</span></td>'
                + '</tr>';
        }
        if (!rows) rows = '<tr><td colspan="5">No SMS. Send one to this modem number and click Refresh.</td></tr>';
        $('#rows').html(rows);
        $('#meta').html('updated: ' + esc(data.updated) + ' &middot; total: ' + (data.count || 0));
    }).fail(function () {
        $('#meta').text('inbox.json not available yet - daemon may be starting');
        $('#rows').html('<tr><td colspan="5">No data.</td></tr>');
    });
}

function refresh() {
    $('#meta').text('syncing with modem...');
    $.getJSON('http://192.168.100.1:8080/cgi-bin/api?action=refresh&_=' + Date.now(), function () { })
        .always(function () { loadInbox(); });
}

function delMsg(store, id) {
    if (!confirm('Delete SMS #' + id + ' from ' + store.toUpperCase() + '?')) return;
    $.getJSON('http://192.168.100.1:8080/cgi-bin/api?action=delete&store=' + store + '&id=' + id + '&_=' + Date.now(),
        function (r) {
            if (r.flag === '1') loadInbox();
            else alert('Delete failed: ' + r.error_info);
        }).fail(function () { alert('API unreachable'); });
}

function toggleCompose() { $('#compose').toggle(); }

function sendSms() {
    var num = $('#c_num').val().trim();
    var text = $('#c_text').val();
    if (!num || !text) { $('#c_status').text('number and text required'); return; }
    $('#c_status').text('sending...');
    $.getJSON('http://192.168.100.1:8080/cgi-bin/api?action=send&num=' + encodeURIComponent(num) +
        '&text=' + encodeURIComponent(text) + '&_=' + Date.now(),
        function (r) {
            $('#c_status').text(r.flag === '1' ? 'send attempted - check recipient' : 'failed: ' + r.error_info);
            if (r.flag === '1') { $('#c_text').val(''); }
        }).fail(function () { $('#c_status').text('API unreachable'); });
}

$(function () {
    loadInbox();
    setInterval(function () { if ($('#autoref').is(':checked')) loadInbox(); }, 10000);
});
