import './index.scss' // include bootstrap css file with own modifications

var xmlHttp = new XMLHttpRequest();
xmlHttp.onreadystatechange = function() {
	if(xmlHttp.readyState == 4 && xmlHttp.status == 200)
		document.querySelectorAll(".version").forEach(function(e) {
			e.textContent = "~>" + xmlHttp.responseText.replace(/['"]+/g, '');
		});
}
xmlHttp.open("GET", "https://code.dlang.org/api/packages/silly/latest", true);
xmlHttp.send(null);