CREATE OR REPLACE TYPE HTM_NUMBER_LIST AS TABLE OF NUMBER;
/

CREATE OR REPLACE TYPE HTM_VECTOR AS OBJECT (
  x NUMBER,
  y NUMBER,
  z NUMBER,

  CONSTRUCTOR FUNCTION HTM_VECTOR(x_val NUMBER, y_val NUMBER, z_val NUMBER) RETURN SELF AS RESULT,
  CONSTRUCTOR FUNCTION HTM_VECTOR(ra NUMBER, dec NUMBER) RETURN SELF AS RESULT,

  MEMBER FUNCTION magnitude RETURN NUMBER,
  MEMBER PROCEDURE normalize,
  MEMBER FUNCTION dot_product(v HTM_VECTOR) RETURN NUMBER,
  MEMBER FUNCTION cross_product(v HTM_VECTOR) RETURN HTM_VECTOR,
  MEMBER FUNCTION to_string RETURN VARCHAR2
);
/

CREATE OR REPLACE TYPE BODY HTM_VECTOR AS
  CONSTRUCTOR FUNCTION HTM_VECTOR(x_val NUMBER, y_val NUMBER, z_val NUMBER) RETURN SELF AS RESULT IS
  BEGIN
    SELF.x := x_val;
    SELF.y := y_val;
    SELF.z := z_val;
    RETURN;
  END;

  CONSTRUCTOR FUNCTION HTM_VECTOR(ra NUMBER, dec NUMBER) RETURN SELF AS RESULT IS
  BEGIN
    -- Implementation will be provided in a package
    SELF.x := 0; -- Placeholder
    SELF.y := 0; -- Placeholder
    SELF.z := 0; -- Placeholder
    RETURN;
  END;

  MEMBER FUNCTION magnitude RETURN NUMBER IS
  BEGIN
    -- Implementation will be provided in a package
    RETURN 0; -- Placeholder
  END;

  MEMBER PROCEDURE normalize IS
  BEGIN
    -- Implementation will be provided in a package
    NULL; -- Placeholder
  END;

  MEMBER FUNCTION dot_product(v HTM_VECTOR) RETURN NUMBER IS
  BEGIN
    -- Implementation will be provided in a package
    RETURN 0; -- Placeholder
  END;

  MEMBER FUNCTION cross_product(v HTM_VECTOR) RETURN HTM_VECTOR IS
  BEGIN
    -- Implementation will be provided in a package
    RETURN HTM_VECTOR(0,0,0); -- Placeholder
  END;

  MEMBER FUNCTION to_string RETURN VARCHAR2 IS
  BEGIN
    RETURN '(' || SELF.x || ', ' || SELF.y || ', ' || SELF.z || ')';
  END;
END;
/

CREATE OR REPLACE TYPE HTM_VERTEX_LIST AS TABLE OF HTM_VECTOR;
/

CREATE OR REPLACE TYPE HTM_ID_RANGE AS OBJECT (
  low_id NUMBER,
  high_id NUMBER,

  CONSTRUCTOR FUNCTION HTM_ID_RANGE(l_id NUMBER, h_id NUMBER) RETURN SELF AS RESULT
);
/

CREATE OR REPLACE TYPE BODY HTM_ID_RANGE AS
  CONSTRUCTOR FUNCTION HTM_ID_RANGE(l_id NUMBER, h_id NUMBER) RETURN SELF AS RESULT IS
  BEGIN
    SELF.low_id := l_id;
    SELF.high_id := h_id;
    RETURN;
  END;
END;
/

CREATE OR REPLACE TYPE HTM_ID_RANGE_LIST AS TABLE OF HTM_ID_RANGE;
/

CREATE OR REPLACE TYPE HTM_NODE AS OBJECT (
  node_id NUMBER,
  parent_id NUMBER,
  level_num NUMBER,
  is_leaf NUMBER, -- 0 or 1
  children_ids HTM_NUMBER_LIST,
  v_ids HTM_NUMBER_LIST,
  w_ids HTM_NUMBER_LIST,

  CONSTRUCTOR FUNCTION HTM_NODE(
    p_node_id NUMBER,
    p_parent_id NUMBER,
    p_level_num NUMBER,
    p_is_leaf NUMBER,
    p_children_ids HTM_NUMBER_LIST,
    p_v_ids HTM_NUMBER_LIST,
    p_w_ids HTM_NUMBER_LIST DEFAULT NULL
  ) RETURN SELF AS RESULT
);
/

CREATE OR REPLACE TYPE BODY HTM_NODE AS
  CONSTRUCTOR FUNCTION HTM_NODE(
    p_node_id NUMBER,
    p_parent_id NUMBER,
    p_level_num NUMBER,
    p_is_leaf NUMBER,
    p_children_ids HTM_NUMBER_LIST,
    p_v_ids HTM_NUMBER_LIST,
    p_w_ids HTM_NUMBER_LIST DEFAULT NULL
  ) RETURN SELF AS RESULT IS
  BEGIN
    SELF.node_id := p_node_id;
    SELF.parent_id := p_parent_id;
    SELF.level_num := p_level_num;
    SELF.is_leaf := p_is_leaf;
    SELF.children_ids := p_children_ids;
    SELF.v_ids := p_v_ids;
    SELF.w_ids := p_w_ids;
    RETURN;
  END;
END;
/

CREATE OR REPLACE TYPE HTM_NODE_LIST AS TABLE OF HTM_NODE;
/

CREATE OR REPLACE TYPE HTM_LAYER_INFO AS OBJECT (
  level_num NUMBER,
  n_nodes NUMBER,
  n_vertices NUMBER,
  n_edges NUMBER,
  first_node_id NUMBER,
  first_vertex_id NUMBER,

  CONSTRUCTOR FUNCTION HTM_LAYER_INFO(
    p_level_num NUMBER,
    p_n_nodes NUMBER,
    p_n_vertices NUMBER,
    p_n_edges NUMBER,
    p_first_node_id NUMBER,
    p_first_vertex_id NUMBER
  ) RETURN SELF AS RESULT
);
/

CREATE OR REPLACE TYPE BODY HTM_LAYER_INFO AS
  CONSTRUCTOR FUNCTION HTM_LAYER_INFO(
    p_level_num NUMBER,
    p_n_nodes NUMBER,
    p_n_vertices NUMBER,
    p_n_edges NUMBER,
    p_first_node_id NUMBER,
    p_first_vertex_id NUMBER
  ) RETURN SELF AS RESULT IS
  BEGIN
    SELF.level_num := p_level_num;
    SELF.n_nodes := p_n_nodes;
    SELF.n_vertices := p_n_vertices;
    SELF.n_edges := p_n_edges;
    SELF.first_node_id := p_first_node_id;
    SELF.first_vertex_id := p_first_vertex_id;
    RETURN;
  END;
END;
/

CREATE OR REPLACE TYPE HTM_LAYER_LIST AS TABLE OF HTM_LAYER_INFO;
/
