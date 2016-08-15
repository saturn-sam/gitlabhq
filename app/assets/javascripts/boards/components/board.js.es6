(() => {
  const Board = Vue.extend({
    props: {
      list: Object,
      disabled: Boolean,
      issueLinkBase: String
    },
    data () {
      return {
        query: '',
        filters: BoardsStore.state.filters
      };
    },
    watch: {
      query () {
        if (this.list.canSearch()) {
          this.list.filters = this.getFilterData();
          this.list.getIssues(true);
        }
      },
      filters: {
        handler () {
          this.list.page = 1;
          this.list.getIssues(true);
        },
        deep: true
      }
    },
    methods: {
      clearSearch () {
        this.query = '';
      },
      getFilterData () {
        if (!this.list.canSearch()) return this.filters;

        const filters = this.filters;
        let queryData = { search: this.query };

        Object.keys(filters).forEach((key) => { queryData[key] = filters[key]; });

        return queryData;
      }
    },
    computed: {
      isPreset () {
        return ['backlog', 'done', 'blank'].indexOf(this.list.type) > -1;
      }
    },
    ready () {
      const options = gl.getBoardSortableDefaultOptions({
        disabled: this.disabled,
        group: 'boards',
        draggable: '.is-draggable',
        handle: '.js-board-handle',
        onUpdate (e) {
          BoardsStore.moveList(e.oldIndex, e.newIndex);
        }
      });

      if (bp.getBreakpointSize() === 'sm' || bp.getBreakpointSize() === 'xs') {
        options.handle = '.js-board-drag-handle';
      }

      this.sortable = Sortable.create(this.$el.parentNode, options);
    },
    beforeDestroy () {
      this.sortable.destroy();
    }
  });

  Vue.component('board', Board)
})();
