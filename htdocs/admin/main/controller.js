'use strict;'

var mainController = [
  '$scope', '$cookies', '$http', '$location', '$window', 'events', 'series',
  function ($scope, $cookies, $http, $location, $window, events, series) {
    $scope.user = JSON.parse(atob($cookies['trialinfo.session'])).passport.user;

    $scope.events = events;
    $scope.series = series;
    $scope.show = {};

    angular.forEach(events, function(event) {
      if (event.closed)
	$scope.closed_events = true;
    });

    angular.forEach(series, function(serie) {
      if (serie.closed)
	$scope.closed_series = true;
    });

    $scope.event_visible = function(event) {
      return $scope.show.closed_events ||
	     !event.closed;
    };

    $scope.serie_visible = function(serie) {
      return $scope.show.closed_series ||
	      !serie.closed;
    };

    $scope.event_name = event_name;

    $scope.new_event = function() {
      $location.path('/event/new/settings');
    };

    $scope.import = function() {
      $location.path('/import');
    };

    $scope.new_serie = function() {
      $location.path('/serie/new');
    };

    $scope.logout = function() {
      $window.location.href = '/logout';
    };
  }];

mainController.resolve = {
  events: [
    '$q', '$http',
    function($q, $http) {
      // FIXME: How to detect an HTTP redirect to the login page here?
      return http_request($q, $http.get('/api/events'));
    }],
  series: [
    '$q', '$http',
    function($q, $http) {
      // FIXME: How to detect an HTTP redirect to the login page here?
      return http_request($q, $http.get('/api/series'));
    }]
};
