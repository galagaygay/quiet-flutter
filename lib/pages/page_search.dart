import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:keyboard_visibility/keyboard_visibility.dart';
import 'package:quiet/pages/page_search_sections.dart';
import 'package:quiet/part/part.dart';
import 'package:quiet/repository/local_search_history.dart';
import 'package:quiet/repository/netease.dart';

class NeteaseSearchPageRoute<T> extends PageRoute<T> {
  NeteaseSearchPageRoute(this._proxyAnimation);

  final ProxyAnimation _proxyAnimation;

  @override
  Color get barrierColor => null;

  @override
  String get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  bool get maintainState => true;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }

  @override
  Animation<double> createAnimation() {
    final Animation<double> animation = super.createAnimation();
    _proxyAnimation?.parent = animation;
    return animation;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return NeteaseSearchPage(
      animation: animation,
    );
  }
}

class NeteaseSearchPage extends StatefulWidget {
  final Animation<double> animation;

  const NeteaseSearchPage({Key key, @required this.animation})
      : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _NeteaseSearchPageState();
  }
}

class _NeteaseSearchPageState extends State<NeteaseSearchPage> {
  final TextEditingController _queryTextController = TextEditingController();

  final FocusNode _focusNode = FocusNode();

  String get query => _queryTextController.text;

  set query(String value) {
    assert(value != null);
    _queryTextController.text = value;
  }

  ///the query of [_SearchResultPage]
  String _searchedQuery = "";

  bool showSuggestion = false;

  bool initialState = true;

  KeyboardVisibilityNotification keyboardVisibilityNotification;

  @override
  void initState() {
    super.initState();
    _queryTextController.addListener(_onQueryTextChanged);
    widget.animation.addStatusListener(_onAnimationStatusChanged);
    _focusNode.addListener(_onFocusChanged);
    keyboardVisibilityNotification = KeyboardVisibilityNotification()
      ..addNewListener(onShow: () {
        setState(() {
          showSuggestion = true;
        });
      }, onHide: () {
        setState(() {
          showSuggestion = false;
        });
      });
  }

  @override
  void dispose() {
    _queryTextController.removeListener(_onQueryTextChanged);
    widget.animation.removeStatusListener(_onAnimationStatusChanged);
    _focusNode.removeListener(_onFocusChanged);
    keyboardVisibilityNotification.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Widget tabs;
    if (!initialState) {
      tabs = TabBar(
          indicator: UnderlineTabIndicator(insets: EdgeInsets.only(bottom: 4)),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: _SECTIONS.map((title) => Tab(child: Text(title))).toList());
    }

    return Stack(
      children: <Widget>[
        DefaultTabController(
          length: _SECTIONS.length,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: theme.primaryColor,
              iconTheme: theme.primaryIconTheme,
              textTheme: theme.primaryTextTheme,
              brightness: theme.primaryColorBrightness,
              leading: BackButton(),
              title: TextField(
                controller: _queryTextController,
                focusNode: _focusNode,
                style: theme.primaryTextTheme.title,
                textInputAction: TextInputAction.search,
                onSubmitted: (String _) => _search(query),
                decoration: InputDecoration(
                    border: InputBorder.none,
                    hintStyle: theme.primaryTextTheme.title,
                    hintText:
                        MaterialLocalizations.of(context).searchFieldLabel),
              ),
              actions: buildActions(context),
              bottom: tabs,
            ),
            body: initialState
                ? _EmptyQuerySuggestionSection(
                    suggestionSelectedCallback: (query) => _search(query))
                : _SearchResultPage(query: _searchedQuery),
          ),
        ),
        SafeArea(
            child: Padding(
                padding: EdgeInsets.only(top: kToolbarHeight),
                child: buildSuggestions(context)))
      ],
    );
  }

  ///start search for keyword
  void _search(String query) {
    if (query.isEmpty) {
      return;
    }
    insertSearchHistory(query);
    _focusNode.unfocus();
    setState(() {
      initialState = false;
      _searchedQuery = query;
      this.query = query;
    });
  }

  void _onQueryTextChanged() {
    setState(() {
      // rebuild ourselves because query changed.
    });
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    widget.animation.removeStatusListener(_onAnimationStatusChanged);
    //we need request focus on text field when first in
    FocusScope.of(context).requestFocus(_focusNode);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (!showSuggestion) {
        setState(() {
          showSuggestion = true;
        });
      }
    } else {
      if (showSuggestion) {
        setState(() {
          showSuggestion = false;
        });
      }
    }
  }

  List<Widget> buildActions(BuildContext context) {
    return <Widget>[
      query.isEmpty
          ? null
          : IconButton(
              tooltip: '清除',
              icon: const Icon(Icons.clear),
              onPressed: () {
                query = '';
              },
            )
    ]..removeWhere((v) => v == null);
  }

  Widget buildSuggestions(BuildContext context) {
    if (!showSuggestion || query.isEmpty) {
      return Container(height: 0, width: 0);
    }
    return _SuggestionsPage(
      query: query,
      onSuggestionSelected: (keyword) {
        query = keyword;
        _search(query);
      },
    );
  }
}

typedef SuggestionSelectedCallback = void Function(String keyword);

///搜索建议
class _SuggestionsPage extends StatefulWidget {
  _SuggestionsPage({@required this.query, @required this.onSuggestionSelected})
      : assert(query != null),
        assert(onSuggestionSelected != null);

  final String query;

  final SuggestionSelectedCallback onSuggestionSelected;

  @override
  State<StatefulWidget> createState() {
    return _SuggestionsPageState();
  }
}

class _SuggestionsPageState extends State<_SuggestionsPage> {
  String _query;

  CancelableOperation _operationDelay;

  @override
  void didUpdateWidget(_SuggestionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _operationDelay?.cancel();
    _operationDelay = CancelableOperation.fromFuture(() async {
      //we should delay some time to load the suggest for query
      await Future.delayed(Duration(milliseconds: 1000));
      return widget.query;
    }())
      ..value.then((keyword) {
        setState(() {
          _query = keyword;
        });
      });
  }

  @override
  void dispose() {
    _operationDelay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      duration: const Duration(milliseconds: 300),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280.0),
        child: Material(
          elevation: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(
                  "搜索 : ${widget.query}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  widget.onSuggestionSelected(widget.query);
                },
              ),
              Loader<List<String>>(
                  key: Key("suggest_$_query"),
                  loadTask: () => neteaseRepository.searchSuggest(_query),
                  loadingBuilder: (context) {
                    return Container();
                  },
                  builder: (context, result) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: result.map((keyword) {
                        return ListTile(
                          title: Text(keyword),
                          onTap: () {
                            widget.onSuggestionSelected(keyword);
                          },
                        );
                      }).toList(),
                    );
                  })
            ],
          ),
        ),
      ),
    );
  }
}

///when query is empty, show default suggestions
///with hot query keyword from network
///with query history from local
class _EmptyQuerySuggestionSection extends StatefulWidget {
  _EmptyQuerySuggestionSection(
      {Key key, @required this.suggestionSelectedCallback})
      : assert(suggestionSelectedCallback != null),
        super(key: key);

  final SuggestionSelectedCallback suggestionSelectedCallback;

  @override
  _EmptyQuerySuggestionSectionState createState() {
    return new _EmptyQuerySuggestionSectionState();
  }
}

class _EmptyQuerySuggestionSectionState
    extends State<_EmptyQuerySuggestionSection> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        Loader<List<String>>(
            loadTask: () => neteaseRepository.searchHotWords(),
            resultVerify: simpleLoaderResultVerify((v) => v != null),
            //hide when failed load hot words
            failedWidgetBuilder: (context, result, msg) => Container(),
            loadingBuilder: (context) {
              return _SuggestionSection(
                title: "热门搜索",
                words: [],
                suggestionSelectedCallback: widget.suggestionSelectedCallback,
              );
            },
            builder: (context, result) {
              return _SuggestionSection(
                title: "热门搜索",
                words: result,
                suggestionSelectedCallback: widget.suggestionSelectedCallback,
              );
            }),
        Loader<List<String>>(
          loadTask: () => getSearchHistory(),
          resultVerify: simpleLoaderResultVerify((v) => v.isNotEmpty),
          //hide when failed load hot words
          failedWidgetBuilder: (context, result, msg) => Container(),
          builder: (context, result) {
            return _SuggestionSection(
              title: "历史搜索",
              words: result,
              suggestionSelectedCallback: widget.suggestionSelectedCallback,
              onDeleteClicked: () async {
                var delete = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        content: Text("确定清空全部历史记录?"),
                        actions: <Widget>[
                          FlatButton(
                              onPressed: () {
                                Navigator.of(context).pop(false);
                              },
                              child: Text("取消")),
                          FlatButton(
                              onPressed: () {
                                Navigator.of(context).pop(true);
                              },
                              child: Text("清空"))
                        ],
                      );
                    });
                if (delete != null && delete) {
                  await clearSearchHistory();
                  setState(() {});
                }
              },
            );
          },
        ),
      ],
    );
  }
}

class _SuggestionSection extends StatelessWidget {
  const _SuggestionSection(
      {Key key,
      @required this.title,
      @required this.words,
      @required this.suggestionSelectedCallback,
      this.onDeleteClicked})
      : assert(title != null),
        assert(words != null),
        assert(suggestionSelectedCallback != null),
        super(key: key);

  final String title;
  final List<String> words;
  final VoidCallback onDeleteClicked;

  final SuggestionSelectedCallback suggestionSelectedCallback;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .subtitle
                          .copyWith(fontWeight: FontWeight.bold, fontSize: 17)),
                ),
                onDeleteClicked == null
                    ? Container()
                    : IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).iconTheme.color,
                        ),
                        onPressed: onDeleteClicked)
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            children: words.map<Widget>((str) {
              return ActionChip(
                label: Text(str),
                onPressed: () {
                  suggestionSelectedCallback(str);
                },
              );
            }).toList(),
          )
        ],
      ),
    );
  }
}

class _SearchResultPage extends StatefulWidget {
  _SearchResultPage({Key key, this.query})
      : assert(query != null && query.isNotEmpty),
        super(key: key);

  final String query;

  @override
  _SearchResultPageState createState() {
    return new _SearchResultPageState();
  }
}

const List<String> _SECTIONS = ["单曲", "视频", "歌手", "专辑", "歌单"];

class _SearchResultPageState extends State<_SearchResultPage> {
  String query;

  @override
  void initState() {
    super.initState();
    query = widget.query;
  }

  @override
  void didUpdateWidget(_SearchResultPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      setState(() {
        query = widget.query;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BoxWithBottomPlayerController(
      TabBarView(
        children: [
          SongsResultSection(query: query, key: Key("SongTab_$query")),
          VideosResultSection(query: query, key: Key("VideoTab_$query")),
          ArtistsResultSection(query: query, key: Key("Artists_$query")),
          AlbumsResultSection(query: query, key: Key("AlbumTab_$query")),
          PlaylistResultSection(query: query, key: Key("PlaylistTab_$query")),
        ],
      ),
    );
  }
}
