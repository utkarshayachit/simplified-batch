/* from vuejs.org/examples/#grid */
export default {
  props: {
    data: Array,
    columns: Array,
    loadingText: String,
  },

  data: () => ({
    selected: [],
  }),

  methods: {
    on_select() {
      this.$emit('selection_changed', this.selected)
    }
  },

  template: `
    <v-data-table disable-filtering disable-pagination hide-default-footer
      loading=true
      loading-text="no datasets present"
      v-model="selected"
      :headers="columns"
      :items="data"
      item-key="name"
      show-select
      @input="on_select"
      >
    </v-data-table>
  `
}